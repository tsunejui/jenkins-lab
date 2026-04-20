#!/usr/bin/env bash
# Create-or-update a Jenkins job from jobs/<NAME>.xml.
# Usage: job-apply.sh <NAME>
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

NAME="${1:?usage: job-apply.sh <NAME>}"
XML="jobs/${NAME}.xml"

[ -f "$XML" ] || { echo "Missing $XML" >&2; exit 1; }

if cli list-jobs 2>/dev/null | grep -qxF "$NAME"; then
    cli update-job "$NAME" < "$XML"
    echo "Job '$NAME' updated."
else
    cli create-job "$NAME" < "$XML"
    echo "Job '$NAME' created."
fi
