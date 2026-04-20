#!/usr/bin/env bash
# Interactively pick a jenkins-envs/*.toml and link it to .mise.local.toml.
set -euo pipefail

ENVS_DIR="jenkins-envs"
LINK=".mise.local.toml"
GUM="mise exec -- gum"

[ -d "$ENVS_DIR" ] || { echo "error: $ENVS_DIR/ not found" >&2; exit 1; }

mapfile -t envs < <(ls "$ENVS_DIR"/*.toml 2>/dev/null | xargs -n1 basename | sed 's/\.toml$//')
if [ "${#envs[@]}" -eq 0 ]; then
    echo "error: no *.toml files in $ENVS_DIR/" >&2
    exit 1
fi

current=""
if [ -L "$LINK" ]; then
    current=$(basename "$(readlink "$LINK")" .toml)
fi

header="Select Jenkins env"
[ -n "$current" ] && header="$header   (current: $current)"

target=$(printf '%s\n' "${envs[@]}" | $GUM choose --header "$header")
[ -n "$target" ] || { echo "aborted"; exit 0; }

# If the link target is a real file (not a symlink), ask before clobbering.
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    $GUM confirm "Overwrite non-symlink $LINK with $ENVS_DIR/$target.toml?" || exit 0
fi

ln -sfn "$ENVS_DIR/$target.toml" "$LINK"
echo "✓ switched: $LINK → $(readlink "$LINK")"
echo
echo "Env preview:"
grep -E '^(JENKINS_URL|JENKINS_ADMIN_ID|DEMO_)' "$ENVS_DIR/$target.toml" \
    | sed -E 's/_PASSWORD.*$/_PASSWORD = ****/; s/_TOKEN.*$/_TOKEN = ****/; s/^/  /'
