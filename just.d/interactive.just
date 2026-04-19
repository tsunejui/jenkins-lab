# ─── interactive (gum) ────────────────────────────────────────────────────────

# Print a styled banner (used by interactive recipes)
[private]
_banner TEXT:
    @{{gum}} style --border normal --margin "0 1" --padding "0 2" --border-foreground 212 "{{TEXT}}"

# Interactively pick an existing job on the controller (prints the name)
[group('interactive')]
pick-job: cli-jar
    @{{cli}} list-jobs | {{gum}} choose --header "Select a job"

# Interactively pick a local jobs/*.xml definition (prints the base name)
[group('interactive')]
pick-local:
    @ls {{jobs_dir}}/*.xml 2>/dev/null | xargs -n1 basename | sed 's/\.xml$//' \
        | {{gum}} choose --header "Select a local job XML"

# Interactive pipeline menu: choose an action, then a job
[group('interactive')]
pipeline: cli-jar
    @just _banner "Jenkins Lab · Pipeline Menu"
    @action=$(printf "%s\n" \
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
      | {{gum}} choose --header "Pipeline action"); \
    test -n "$action" || exit 0; \
    act=$(echo "$action" | awk '{print $1}'); \
    case "$act" in \
        list) \
            just job-list ;; \
        apply|create|update|dump) \
            name=$(just pick-local); test -n "$name" || exit 0; \
            just "job-$act" "$name" ;; \
        delete) \
            name=$(just pick-job); test -n "$name" || exit 0; \
            {{gum}} confirm "Delete job '$name'?" \
                && {{cli}} delete-job "$name" \
                && echo "Job '$name' deleted." ;; \
        *) \
            name=$(just pick-job); test -n "$name" || exit 0; \
            just "job-$act" "$name" ;; \
    esac

# Interactive build: pick any job, trigger and stream
[group('interactive')]
build-i: cli-jar
    @name=$(just pick-job); test -n "$name" || exit 0; just job-build "$name"

# Interactive log viewer
[group('interactive')]
log-i: cli-jar
    @name=$(just pick-job); test -n "$name" || exit 0; just job-log "$name"

# Interactive apply from jobs/*.xml
[group('interactive')]
apply-i: cli-jar
    @name=$(just pick-local); test -n "$name" || exit 0; just job-apply "$name"
