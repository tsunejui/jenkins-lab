#!/usr/bin/env bash
# Runtime state of a pipeline build (default: lastBuild).
# Pulled from the REST API since the CLI has no structured query for this.
#
# Usage: pipeline-status.sh <NAME> [BUILD]     (BUILD: number or lastBuild)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

NAME="${1:?usage: pipeline-status.sh <NAME> [BUILD]}"
BUILD="${2:-lastBuild}"
JPATH=$(_job_path "$NAME")

tree="number,result,duration,timestamp,url,building"
if ! info=$(_jcurl "$JPATH/$BUILD/api/json?tree=$tree"); then
    echo "no build for $NAME/$BUILD" >&2
    exit 1
fi

IFS=$'\t' read -r n result dur ts url building < <(
    printf '%s' "$info" \
      | _jq -r '[.number,(.result // "RUNNING"),.duration,.timestamp,.url,.building] | @tsv'
)

echo "Job           : $NAME"
echo "Build         : #$n"
echo "Result        : $result"
echo "Duration      : ${dur}ms"
echo "Started       : $(_when "$ts")"
echo "URL           : $url"
[ "$building" = "true" ] && echo "In progress   : yes"

# Stage breakdown via wfapi (pipeline-stage-view plugin).
if wf=$(_jcurl "$JPATH/$BUILD/wfapi/describe" 2>/dev/null); then
    echo
    echo "Stages:"
    printf '%s' "$wf" \
      | _jq -r '.stages[] | [.name,.status,.durationMillis] | @tsv' \
      | while IFS=$'\t' read -r sname sstatus sdur; do
            printf "  %-18s %-10s %6sms\n" "$sname" "$sstatus" "$sdur"
        done
else
    echo
    echo "(stage info unavailable — requires pipeline-stage-view plugin)"
fi

# Recent build history only when asking for the last build.
if [ "$BUILD" = "lastBuild" ]; then
    hist=$(_jcurl "$JPATH/api/json?tree=builds[number,result,duration,timestamp]" \
             | _jq -r '(.builds // [])[:8] | .[] | [.number,(.result // "RUNNING"),.duration,.timestamp] | @tsv')
    if [ -n "$hist" ]; then
        echo
        echo "Recent builds:"
        while IFS=$'\t' read -r bn bresult bdur bts; do
            printf "  #%-4s %-8s %6sms  %s\n" "$bn" "$bresult" "$bdur" "$(_when "$bts")"
        done <<< "$hist"
    fi
fi
