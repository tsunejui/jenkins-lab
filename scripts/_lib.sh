# Shared helpers for Jenkins Lab shell scripts.
# Source this file; do not execute directly.
#
# Required env (exported by justfile or mise):
#   JENKINS_URL, JENKINS_ADMIN_ID, JENKINS_ADMIN_PASSWORD, JENKINS_CLI_JAR

: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_ADMIN_ID:?JENKINS_ADMIN_ID is required}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is required}"
: "${JENKINS_CLI_JAR:=./tools/jenkins-cli.jar}"

# Run jenkins-cli.jar with auth. Delegates to scripts/jenkins-cli.sh so the
# invocation gets echoed (with password masked) once, from a single place.
cli() {
    "$(dirname "${BASH_SOURCE[0]}")/jenkins-cli.sh" "$@"
}

# Run jq via mise so the pinned version is always used.
_jq() {
    mise exec -- jq "$@"
}

# Authenticated curl to a Jenkins path. Extra args passed through.
# Usage: _jcurl <path> [curl-flags...]
_jcurl() {
    local path="$1"; shift
    curl -fsSg -u "$JENKINS_ADMIN_ID:$JENKINS_ADMIN_PASSWORD" \
        "$@" "$JENKINS_URL$path"
}

# Cross-platform "epoch ms → ISO-8601 local time".
_when() {
    local ms="$1"
    local sec=$((ms / 1000))
    date -r "$sec" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null \
        || date -d "@$sec" "+%Y-%m-%dT%H:%M:%S"
}

# Convert a Jenkins full-name into a REST/CLI URL path so jobs inside folders
# resolve correctly. Examples:
#   hello-world         → /job/hello-world
#   folder/pipeline     → /job/folder/job/pipeline
#   a/b/c               → /job/a/job/b/job/c
# Uses sed instead of bash parameter expansion — macOS' default bash 3.2
# keeps literal backslashes in `${var//\//\/job\/}` replacements.
_job_path() {
    printf '/job/%s' "$(printf '%s' "$1" | sed 's|/|/job/|g')"
}
