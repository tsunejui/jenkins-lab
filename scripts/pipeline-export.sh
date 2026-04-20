#!/usr/bin/env bash
# Export a pipeline's config, metadata, and last-build artefacts.
# Usage: pipeline-export.sh <NAME> [DIR]   (DIR defaults to ./exports)
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

NAME="${1:?usage: pipeline-export.sh <NAME> [DIR]}"
DIR="${2:-./exports}"

outdir="$DIR/$NAME"
mkdir -p "$outdir"

echo "Exporting '$NAME' → $outdir/"

# Fetch binary blob to a file, or formatted JSON via jq.
# Usage: grab <path> <outfile> [json]
grab() {
    local path="$1" outfile="$2" fmt="${3:-bin}"
    if [ "$fmt" = "json" ]; then
        _jcurl "$path" | _jq . > "$outfile"
    else
        _jcurl "$path" -o "$outfile"
    fi
    local size; size=$(wc -c < "$outfile" | tr -d ' ')
    echo "  $outfile  ($size bytes)"
}

# config.xml — fatal if missing (job doesn't exist)
if ! grab "$(_job_path "$NAME")/config.xml" "$outdir/config.xml"; then
    echo "cannot fetch job '$NAME'" >&2
    exit 1
fi

grab "$(_job_path "$NAME")/api/json" "$outdir/info.json" json

lb=$(_jq -r '.lastBuild.number // empty' "$outdir/info.json")
if [ -z "$lb" ]; then
    echo "  (no builds yet → skipping build/stage/console)"
    exit 0
fi

grab "$(_job_path "$NAME")/$lb/api/json" "$outdir/last-build.json" json
grab "$(_job_path "$NAME")/$lb/wfapi/describe" "$outdir/stages.json" json \
    || echo "  stages.json skipped"
grab "$(_job_path "$NAME")/$lb/consoleText" "$outdir/console.log" \
    || echo "  console.log skipped"
