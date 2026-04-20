#!/usr/bin/env bash
# Static definition of a pipeline — pulled from config.xml via the Jenkins CLI
# (`get-job`). No runtime / build state here; use pipeline-status for that.
#
# Usage: pipeline-info.sh <NAME>
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

NAME="${1:?usage: pipeline-info.sh <NAME>}"

if ! xml=$(cli get-job "$NAME" 2>&1); then
    echo "cannot fetch job '$NAME': $xml" >&2
    exit 1
fi

# Extract first <TAG>...</TAG> text content (single-line tags only).
# `|| true` so an absent tag doesn't trip set -o pipefail.
extract() {
    printf '%s' "$xml" \
      | grep -oE "<$1>[^<]*</$1>" \
      | head -1 \
      | sed -E "s/<[^>]*>//g" \
      || true
}

echo "Name          : $NAME"
desc=$(extract description);     [ -n "$desc" ]     && echo "Description   : $desc"
disabled=$(extract disabled);    [ -n "$disabled" ] && echo "Disabled      : $disabled"
keepdeps=$(extract keepDependencies); [ -n "$keepdeps" ] && echo "KeepDeps      : $keepdeps"

# Stage labels — best-effort regex on the Groovy script. Works for
# Declarative pipelines with string-literal stage names; dynamic / parallel
# stages may be under-represented.
stages=$(printf '%s' "$xml" \
  | awk '/<script>/,/<\/script>/' \
  | sed -e 's/&apos;/'"'"'/g' -e 's/&quot;/"/g' \
  | grep -oE "stage\(['\"][^'\"]+['\"]\)" \
  | sed -E "s/stage\(['\"](.+)['\"]\)/  \1/" \
  || true)

if [ -n "$stages" ]; then
    echo
    echo "Declared stages:"
    printf '%s\n' "$stages"
fi

echo
echo "Definition:"
echo "  just cli get-job $NAME          # raw config.xml"
echo "  just job-dump    $NAME          # save to jobs/$NAME.xml"
echo "  just pipeline-status $NAME      # runtime state of last build"
