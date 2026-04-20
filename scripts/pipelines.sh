#!/usr/bin/env bash
# List WorkflowJob entries on the controller with status + URL.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

response=$(_jcurl "/api/json?tree=jobs[name,_class,color,url]")

# Extract pipeline rows as TSV: name \t color \t url
rows=$(printf '%s' "$response" \
    | _jq -r '.jobs
              | map(select(._class | endswith("WorkflowJob")))
              | .[] | [.name, (.color // "notbuilt"), .url] | @tsv')

if [ -z "$rows" ]; then
    echo "(no pipeline jobs)"
    exit 0
fi

# Compute max name width from TSV first column.
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
