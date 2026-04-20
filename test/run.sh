#!/usr/bin/env bash
# Smoke-test every sample .gitlab-ci.yml under example/j2gitlab/samples/ with
# gitlab-ci-local: parse + list jobs (cheap) for all, then execute hello-world
# end-to-end so we have at least one full run proving the converter output is
# consumable by a real GitLab runner.
set -euo pipefail

SAMPLES_DIR="example/j2gitlab/samples"
FIXTURES_DIR="test/fixtures"

# Echo each gitlab-ci-local invocation to the controlling terminal so it
# shows even when the caller captures stdout and stderr (e.g. `gcl ...
# > out.log 2> err.log`). Fall back to stderr when no tty is available.
if { : > /dev/tty; } 2>/dev/null; then gcl_log=/dev/tty; else gcl_log=/dev/stderr; fi
gcl() {
    { printf '    + gitlab-ci-local'; printf ' %q' "$@"; printf '\n'; } > "$gcl_log"
    mise exec npm:gitlab-ci-local -- gitlab-ci-local "$@"
}

# gitlab-ci-local refuses absolute --cwd paths, so translate to a relative one.
rel() { python3 -c "import os,sys;print(os.path.relpath(sys.argv[1]))" "$1"; }

pass=0
fail=0
failures=()

# ── parse / list every sample (fast; no jobs actually executed) ──────────────
for yml in "$SAMPLES_DIR"/*.gitlab-ci.yml; do
    name=$(basename "$yml" .gitlab-ci.yml)
    tmp=$(mktemp -d)
    cp "$yml" "$tmp/.gitlab-ci.yml"
    [ -f "$FIXTURES_DIR/$name.variables.yml" ] && \
        cp "$FIXTURES_DIR/$name.variables.yml" "$tmp/.gitlab-ci-local-variables.yml"

    printf "=== %-15s  parse + list ===\n" "$name"
    if gcl --cwd "$(rel "$tmp")" --list-json > "$tmp/out.log" 2> "$tmp/err.log"; then
        jobs=$(mise exec -- jq 'length' "$tmp/out.log" 2>/dev/null || echo "?")
        echo "    OK — $jobs job(s) detected"
        pass=$((pass + 1))
    else
        echo "    FAIL"
        sed 's/^/      /' "$tmp/out.log"
        failures+=("$name")
        fail=$((fail + 1))
    fi
    rm -rf "$tmp"
done

echo
echo "Parsing: $pass/$((pass + fail)) pipelines passed."
if [ "$fail" -gt 0 ]; then
    echo "Failed: ${failures[*]}"
    exit 1
fi

# ── run hello-world end-to-end ───────────────────────────────────────────────
echo
echo "=== hello-world               execute   ==="
tmp=$(mktemp -d)
cp "$SAMPLES_DIR/hello-world.gitlab-ci.yml" "$tmp/.gitlab-ci.yml"
if gcl --cwd "$(rel "$tmp")" > "$tmp/run.log" 2>&1; then
    grep -E 'PASS|FAIL|finished' "$tmp/run.log" | sed 's/^/    /'
    echo "    end-to-end OK"
else
    echo "    end-to-end FAIL"
    cat "$tmp/run.log" | sed 's/^/      /'
    rm -rf "$tmp"
    exit 1
fi
rm -rf "$tmp"

echo
echo "All checks passed."
