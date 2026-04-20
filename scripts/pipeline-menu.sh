#!/usr/bin/env bash
# Interactive pipeline menu. Selects an action, then a job, then delegates
# back to the matching `just job-*` recipe.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

GUM="mise exec -- gum"

$GUM style --border normal --margin "0 1" --padding "0 2" \
    --border-foreground 212 "Jenkins Lab · Pipeline Menu"

action=$(printf "%s\n" \
    "build    — trigger a build and stream output" \
    "log      — show console log for lastBuild" \
    "last     — show last build summary" \
    "open     — open job page in browser" \
    "list     — list all jobs" \
    "apply    — create-or-update from local XML" \
    "create   — create from local XML" \
    "update   — update from local XML" \
    "dump     — save controller job to local XML" \
    "enable   — enable job" \
    "disable  — disable job" \
    "delete   — delete job (with confirm)" \
  | $GUM choose --header "Pipeline action")

[ -n "$action" ] || exit 0
act=$(echo "$action" | awk '{print $1}')

case "$act" in
    list)
        just job-list
        ;;
    apply|create|update|dump)
        name=$(just pick-local); [ -n "$name" ] || exit 0
        just "job-$act" "$name"
        ;;
    delete)
        name=$(just pick-job); [ -n "$name" ] || exit 0
        if $GUM confirm "Delete job '$name'?"; then
            cli delete-job "$name"
            echo "Job '$name' deleted."
        fi
        ;;
    *)
        name=$(just pick-job); [ -n "$name" ] || exit 0
        just "job-$act" "$name"
        ;;
esac
