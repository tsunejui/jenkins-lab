#!/usr/bin/env bash
# Bulk-apply every jobs/*.xml to the controller (create-or-update).
set -euo pipefail
shopt -s nullglob
source "$(dirname "$0")/_lib.sh"

existing="$(cli list-jobs 2>/dev/null || true)"

for f in jobs/*.xml; do
    n=$(basename "$f" .xml)
    if echo "$existing" | grep -qxF "$n"; then
        cli update-job "$n" < "$f" && echo "updated : $n"
    else
        cli create-job "$n" < "$f" && echo "created : $n"
    fi
done
