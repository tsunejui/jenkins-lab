# ─── Jenkins CLI helpers ──────────────────────────────────────────────────────

# Wait until Jenkins /login returns 200 (used before CLI calls)
[group('cli')]
wait-ready:
    @curl -fsS -o /dev/null "{{jenkins_url}}/login" 2>/dev/null \
        || {{gum}} spin --show-error --timeout=120s \
             --title "Waiting for Jenkins to become ready..." -- \
             bash -c 'until curl -fsS -o /dev/null "{{jenkins_url}}/login"; do sleep 2; done'

# Download jenkins-cli.jar from the running server into {{tools_dir}} (cached)
[group('cli')]
cli-jar: wait-ready
    @mkdir -p {{tools_dir}}
    @test -f {{cli_jar}} || curl -fsSo {{cli_jar}} "{{jenkins_url}}/jnlpJars/jenkins-cli.jar"

# Re-download jenkins-cli.jar (e.g. after a Jenkins upgrade)
[group('cli')]
cli-jar-refresh:
    @rm -f {{cli_jar}}
    @just cli-jar
    @echo "Refreshed: {{cli_jar}}"

# Run an arbitrary jenkins-cli command, e.g. `just cli help`
[group('cli')]
cli *ARGS: cli-jar
    @{{cli}} {{ARGS}}

# Reload JCasC without restarting Jenkins
[group('cli')]
reload-casc: cli-jar
    @{{cli}} reload-configuration-as-code
    @echo "JCasC reloaded."
