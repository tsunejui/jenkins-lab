#!/usr/bin/env bash
# Block until Jenkins /login is reachable (with a gum spinner on slow paths).
set -euo pipefail

: "${JENKINS_URL:?JENKINS_URL is required}"

if curl -fsS -o /dev/null "$JENKINS_URL/login" 2>/dev/null; then
    exit 0
fi

mise exec -- gum spin --show-error --timeout=120s \
    --title "Waiting for Jenkins to become ready..." -- \
    bash -c 'until curl -fsS -o /dev/null "$0/login"; do sleep 2; done' "$JENKINS_URL"
