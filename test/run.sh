#!/usr/bin/env bash
# Run one (or all) testcase(s) defined in test/testcases.yaml against
# gitlab-ci-local.
#
#   Interactive:  ./test/run.sh
#   Direct:       ./test/run.sh <case-name>
#   All (lint):   ./test/run.sh all
set -euo pipefail

CASES_FILE="test/testcases.yaml"
[ -f "$CASES_FILE" ] || { echo "error: $CASES_FILE not found (run from repo root)" >&2; exit 1; }

# ── helpers ─────────────────────────────────────────────────────────────────
YQ="mise exec -- yq"
JQ="mise exec -- jq"
GUM="mise exec -- gum"
GCL="mise exec npm:gitlab-ci-local -- gitlab-ci-local"

# Echo each gitlab-ci-local invocation to the controlling terminal so it
# shows even if the caller redirects stdout/stderr.
if { : > /dev/tty; } 2>/dev/null; then log=/dev/tty; else log=/dev/stderr; fi
gcl() {
    { printf '    + gitlab-ci-local'; printf ' %q' "$@"; printf '\n'; } > "$log"
    $GCL "$@"
}

# gitlab-ci-local rejects absolute --cwd values.
rel() { python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1]))' "$1"; }

# ── pick the case (interactive fallback) ────────────────────────────────────
choice="${1:-}"

if [ -z "$choice" ]; then
    # Build "name — description" options, plus a leading "all" row.
    options=$(
        printf 'all — parse every case (lint-only, fast)\n'
        $YQ -r '.cases | to_entries | .[] | "\(.key) — \(.value.description)"' "$CASES_FILE"
    )
    choice=$(printf '%s\n' "$options" | $GUM choose --header "Pick a testcase")
    [ -n "$choice" ] || { echo "aborted"; exit 0; }
    choice=${choice%% *}   # drop the " — description" tail
fi

# ── run a single case: parse/list + execute ────────────────────────────────
run_one() {
    local name="$1"
    local pipeline variables

    pipeline=$($YQ -r ".cases.\"$name\".pipeline // \"\"" "$CASES_FILE")
    [ -n "$pipeline" ] || { echo "error: testcase '$name' not found" >&2; return 1; }
    [ -f "$pipeline" ] || { echo "error: pipeline missing: $pipeline" >&2; return 1; }

    variables=$($YQ -r ".cases.\"$name\".variables // \"\"" "$CASES_FILE")

    local tmp rel_path
    tmp=$(mktemp -d)
    cp "$pipeline" "$tmp/.gitlab-ci.yml"
    if [ -n "$variables" ] && [ -f "$variables" ]; then
        cp "$variables" "$tmp/.gitlab-ci-local-variables.yml"
    fi
    rel_path=$(rel "$tmp")

    printf '\n=== %-18s %s ===\n' "$name" "$(date -Iseconds)"
    echo "  pipeline  : $pipeline"
    [ -n "$variables" ] && echo "  variables : $variables"
    echo
    echo "--- parse + list ---"
    gcl --cwd "$rel_path" --list-json > "$tmp/out.json" 2> "$tmp/err.log" || {
        echo "    FAIL"
        sed 's/^/      /' "$tmp/err.log"
        rm -rf "$tmp"
        return 1
    }
    jobs=$($JQ 'length' "$tmp/out.json" 2>/dev/null || echo '?')
    echo "    OK — $jobs job(s) detected"

    echo
    echo "--- execute ---"
    if gcl --cwd "$rel_path" > "$tmp/run.log" 2>&1; then
        grep -E 'PASS|FAIL|finished' "$tmp/run.log" | sed 's/^/    /'
    else
        echo "    FAIL"
        cat "$tmp/run.log" | sed 's/^/      /'
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
}

# ── parse/list every case; no execution ────────────────────────────────────
run_all_lint() {
    local pass=0 fail=0 failures=()
    local names
    names=$($YQ -r '.cases | keys | .[]' "$CASES_FILE")

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local pipeline variables tmp rel_path
        pipeline=$($YQ -r ".cases.\"$name\".pipeline" "$CASES_FILE")
        variables=$($YQ -r ".cases.\"$name\".variables // \"\"" "$CASES_FILE")

        tmp=$(mktemp -d)
        cp "$pipeline" "$tmp/.gitlab-ci.yml"
        [ -n "$variables" ] && [ -f "$variables" ] && \
            cp "$variables" "$tmp/.gitlab-ci-local-variables.yml"
        rel_path=$(rel "$tmp")

        printf '=== %-18s parse + list ===\n' "$name"
        if gcl --cwd "$rel_path" --list-json > "$tmp/out.json" 2> "$tmp/err.log"; then
            jobs=$($JQ 'length' "$tmp/out.json" 2>/dev/null || echo '?')
            echo "    OK — $jobs job(s) detected"
            pass=$((pass + 1))
        else
            echo "    FAIL"
            sed 's/^/      /' "$tmp/err.log"
            failures+=("$name")
            fail=$((fail + 1))
        fi
        rm -rf "$tmp"
    done <<< "$names"

    echo
    echo "Parsing: $pass/$((pass + fail)) cases passed"
    if [ "$fail" -gt 0 ]; then
        echo "Failed: ${failures[*]}"
        return 1
    fi
}

# ── dispatch ───────────────────────────────────────────────────────────────
case "$choice" in
    all) run_all_lint ;;
    *)   run_one "$choice" ;;
esac

echo
echo "All checks passed."
