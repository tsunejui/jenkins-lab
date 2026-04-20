#!/usr/bin/env bash
# Print a consolidated summary of a single Jenkins pipeline.
# Usage: pipeline-info.sh <NAME>
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

NAME="${1:?usage: pipeline-info.sh <NAME>}"

tree="name,_class,description,buildable,disabled,nextBuildNumber,url,color,lastBuild[number,result,duration,timestamp,url],builds[number,result,duration,timestamp]"
if ! job=$(_jcurl "/job/$NAME/api/json?tree=$tree" 2>&1); then
    echo "cannot fetch job '$NAME': $job" >&2
    exit 1
fi

# ── header ───────────────────────────────────────────────────────────────────
printf "Name          : %s\n" "$(printf '%s' "$job" | _jq -r '.name')"
printf "Class         : %s\n" "$(printf '%s' "$job" | _jq -r '._class | split(".") | last')"
printf "URL           : %s\n" "$(printf '%s' "$job" | _jq -r '.url')"

desc=$(printf '%s' "$job" | _jq -r '.description // empty')
[ -n "$desc" ] && printf "Description   : %s\n" "$desc"

printf "Buildable     : %s\n" "$(printf '%s' "$job" | _jq -r '.buildable')"
if [ "$(printf '%s' "$job" | _jq -r '.disabled')" = "true" ]; then
    echo "Disabled      : True"
fi
printf "Next build #  : %s\n" "$(printf '%s' "$job" | _jq -r '.nextBuildNumber')"
printf "Color         : %s\n" "$(printf '%s' "$job" | _jq -r '.color // "null"')"

# ── last build ───────────────────────────────────────────────────────────────
if [ "$(printf '%s' "$job" | _jq -r '.lastBuild')" = "null" ]; then
    echo
    echo "(no builds yet)"
    exit 0
fi

IFS=$'\t' read -r n result dur ts url < <(
    printf '%s' "$job" \
      | _jq -r '.lastBuild | [.number, (.result // "RUNNING"), .duration, .timestamp, .url] | @tsv'
)
echo
printf "Last build    : #%s %s  duration=%sms  at %s\n" "$n" "$result" "$dur" "$(_when "$ts")"
printf "                %s\n" "$url"

# ── stages (wfapi) ───────────────────────────────────────────────────────────
if wf=$(_jcurl "/job/$NAME/lastBuild/wfapi/describe" 2>/dev/null); then
    echo
    echo "Stages (last build):"
    printf '%s' "$wf" \
      | _jq -r '.stages[] | [.name, .status, .durationMillis] | @tsv' \
      | while IFS=$'\t' read -r sname sstatus sdur; do
            printf "  %-18s %-10s %6sms\n" "$sname" "$sstatus" "$sdur"
        done
else
    echo
    echo "(stage info unavailable)"
fi

# ── recent builds ────────────────────────────────────────────────────────────
builds=$(printf '%s' "$job" \
    | _jq -r '(.builds // [])[:8] | .[] | [.number, (.result // "RUNNING"), .duration, .timestamp] | @tsv')

if [ -n "$builds" ]; then
    echo
    echo "Recent builds:"
    while IFS=$'\t' read -r n result dur ts; do
        printf "  #%-4s %-8s %6sms  %s\n" "$n" "$result" "$dur" "$(_when "$ts")"
    done <<< "$builds"
fi
