# ─── Jenkins container lifecycle ──────────────────────────────────────────────

# Initialize local data directory
[group('jenkins')]
init:
    mkdir -p {{data_dir}}
    @echo "Data directory ready at {{data_dir}}"

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
up: init
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
