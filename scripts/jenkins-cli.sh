#!/usr/bin/env bash
# Thin wrapper around jenkins-cli.jar that echoes the full invocation
# (password masked) before running. Used by both the justfile's {{cli}}
# variable and the cli() helper in scripts/_lib.sh so every CLI call in
# the project gets logged the same way.
set -euo pipefail

: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_ADMIN_ID:?JENKINS_ADMIN_ID is required}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is required}"
: "${JENKINS_CLI_JAR:=./tools/jenkins-cli.jar}"

# Print to the controlling terminal when one is attached so that callers
# like `x=$(cli ... 2>&1)` or `cli ... 2>/dev/null` can't swallow the log.
# Fall back to stderr in headless environments (CI without a tty).
if { : > /dev/tty; } 2>/dev/null; then
    _cli_log=/dev/tty
else
    _cli_log=/dev/stderr
fi

{
    printf '    + jenkins-cli -s %s -auth %s:**** ' \
        "$JENKINS_URL" "$JENKINS_ADMIN_ID"
    printf '%q ' "$@"
    printf '\n'
} > "$_cli_log"

exec mise exec -- java -jar "$JENKINS_CLI_JAR" \
    -s "$JENKINS_URL" \
    -auth "$JENKINS_ADMIN_ID:$JENKINS_ADMIN_PASSWORD" \
    "$@"
