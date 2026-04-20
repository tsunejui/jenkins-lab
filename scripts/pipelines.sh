#!/usr/bin/env bash
# List every WorkflowJob reachable from the controller — recursively walks
# Folders, OrganizationFolders, and MultiBranchProjects so jobs nested at
# any depth show up (e.g. `team/project/main`).
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

# fetch_pipelines <api_path> <display_prefix>
#   api_path       — path under JENKINS_URL for this container
#                    ("" at root, "/job/folder" for a folder, etc.)
#   display_prefix — folder path displayed before the job name
#                    ("" at root, "folder/" for a folder, etc.)
fetch_pipelines() {
    local api_path="$1" prefix="$2"
    local json
    json=$(_jcurl "$api_path/api/json?tree=jobs[name,_class,color,url]") || return 0

    # Emit WorkflowJob rows: full-path-name \t color \t url
    printf '%s' "$json" | _jq -r --arg p "$prefix" '
        .jobs[]?
        | select(._class | endswith("WorkflowJob"))
        | [($p + .name), (.color // "notbuilt"), .url] | @tsv'

    # Recurse into folder-like containers. Use the child's own `url` field so
    # we never have to URL-encode special characters ourselves.
    local base="${JENKINS_URL%/}"
    while IFS=$'\t' read -r name child_url; do
        [ -z "$name" ] && continue
        local child_path="${child_url%/}"
        child_path="${child_path#"$base"}"
        fetch_pipelines "$child_path" "$prefix$name/"
    done < <(printf '%s' "$json" | _jq -r '
        .jobs[]?
        | select(._class | test("Folder$|OrganizationFolder$|MultiBranchProject$"))
        | [.name, .url] | @tsv')
}

rows=$(fetch_pipelines "" "")

if [ -z "$rows" ]; then
    echo "(no pipeline jobs)"
    exit 0
fi

nw=$(printf '%s\n' "$rows" | awk -F'\t' '{ if (length($1) > m) m = length($1) } END { print m }')

printf "%-*s  %-18s  %s\n" "$nw" "NAME" "STATUS" "URL"
printf -- '-%.0s' $(seq 1 $((nw + 62))); echo

while IFS=$'\t' read -r name color url; do
    running=""
    case "$color" in *_anime) running=" (running)"; color="${color%_anime}";; esac
    case "$color" in
        blue)     status="SUCCESS"   ;;
        red)      status="FAILED"    ;;
        yellow)   status="UNSTABLE"  ;;
        aborted)  status="ABORTED"   ;;
        disabled) status="DISABLED"  ;;
        notbuilt) status="NEVER_RUN" ;;
        *)        status=$(echo "$color" | tr '[:lower:]' '[:upper:]') ;;
    esac
    printf "%-*s  %-18s  %s\n" "$nw" "$name" "${status}${running}" "$url"
done <<< "$rows"
