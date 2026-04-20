# Shared helpers for Jenkins Lab shell scripts.
# Source this file; do not execute directly.
#
# Required env (exported by justfile or mise):
#   JENKINS_URL, JENKINS_ADMIN_ID, JENKINS_ADMIN_PASSWORD, JENKINS_CLI_JAR

: "${JENKINS_URL:?JENKINS_URL is required}"
: "${JENKINS_ADMIN_ID:?JENKINS_ADMIN_ID is required}"
: "${JENKINS_ADMIN_PASSWORD:?JENKINS_ADMIN_PASSWORD is required}"
: "${JENKINS_CLI_JAR:=./tools/jenkins-cli.jar}"

# Run jenkins-cli.jar with auth. Uses mise exec so Java 21 is guaranteed.
cli() {
    mise exec -- java -jar "$JENKINS_CLI_JAR" \
        -s "$JENKINS_URL" \
        -auth "$JENKINS_ADMIN_ID:$JENKINS_ADMIN_PASSWORD" \
        "$@"
}
