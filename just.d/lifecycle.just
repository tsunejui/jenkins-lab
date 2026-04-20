# ─── Jenkins container lifecycle ──────────────────────────────────────────────

# First-time setup: mise install + link dev env + mkdir data (idempotent)
[group('jenkins')]
init:
    @mise install
    @if [ ! -e .mise.local.toml ]; then \
        ln -sfn jenkins-envs/dev.toml .mise.local.toml; \
        echo "✓ linked .mise.local.toml → jenkins-envs/dev.toml"; \
    else \
        echo "✓ .mise.local.toml already present (leaving as-is)"; \
    fi
    @mkdir -p {{data_dir}}
    @echo "✓ data directory: {{data_dir}}"
    @echo
    @echo "Active env:"
    @if [ -L .mise.local.toml ]; then \
        echo "  .mise.local.toml → $(readlink .mise.local.toml)"; \
    else \
        echo "  .mise.local.toml (regular file — your own overrides)"; \
    fi

# Interactively switch .mise.local.toml to a file under jenkins-envs/
[group('jenkins')]
jenkins-envs:
    @./scripts/jenkins-envs.sh

# Build the custom Jenkins image (plugins + init hooks)
[group('jenkins')]
build:
    {{compose}} build {{service}}

# Pull base image layers
[group('jenkins')]
pull:
    {{compose}} pull {{service}}

# Start Jenkins (builds image if needed)
[group('jenkins')]
up:
    @mkdir -p {{data_dir}}
    {{compose}} up -d --build {{service}}
    @echo "Jenkins starting at {{jenkins_url}}"

# Stop and remove the Jenkins container (data persists)
[group('jenkins')]
down:
    {{compose}} down

# Restart the Jenkins container
[group('jenkins')]
restart:
    {{compose}} restart {{service}}

# Show container status
[group('jenkins')]
status:
    {{compose}} ps

# Tail Jenkins logs (Ctrl+C to exit)
[group('jenkins')]
logs:
    {{compose}} logs -f --tail=200 {{service}}

# Open a bash shell inside the Jenkins container
[group('jenkins')]
shell:
    {{compose}} exec {{service}} bash

# Print Jenkins version running in the container
[group('jenkins')]
version:
    @{{compose}} exec {{service}} sh -c 'java -jar /usr/share/jenkins/jenkins.war --version'

# Open Jenkins UI in the default browser (macOS/Linux)
[group('jenkins')]
open:
    @command -v open >/dev/null && open {{jenkins_url}} || xdg-open {{jenkins_url}}

# Rebuild image and recreate container
[group('jenkins')]
upgrade:
    {{compose}} build --pull {{service}}
    {{compose}} up -d --force-recreate {{service}}

# Destroy container + local data, then rebuild and start fresh
[group('jenkins')]
[confirm("Full re-init: wipe ./data/jenkins_home and rebuild the image. Continue?")]
reinit:
    {{compose}} down -v
    rm -rf {{data_dir}}
    {{compose}} build --pull {{service}}
    {{compose}} up -d --force-recreate {{service}}
    @echo "Fresh Jenkins starting at {{jenkins_url}}"

# Back up jenkins_home to a timestamped tar.gz
[group('jenkins')]
backup:
    mkdir -p backups
    tar -czf "backups/jenkins_home-$(date +%Y%m%d-%H%M%S).tar.gz" -C ./data jenkins_home
    @ls -lh backups | tail -n 1

# Remove container AND local data (destructive)
[group('jenkins')]
[confirm("This will delete all Jenkins data in ./data/jenkins_home. Continue?")]
clean:
    {{compose}} down -v
    rm -rf {{data_dir}}
    @echo "Jenkins data wiped."
