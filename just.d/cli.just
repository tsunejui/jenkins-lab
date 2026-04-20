# ─── Jenkins CLI helpers ──────────────────────────────────────────────────────

# Wait until Jenkins /login returns 200 (used before CLI calls)
[group('cli')]
wait-ready:
    @./scripts/wait-ready.sh

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

# Re-apply JCasC (jcasc/jenkins.yaml) without restarting Jenkins
[group('cli')]
reload-casc: cli-jar
    @{{cli}} apply-configuration
    @echo "JCasC re-applied."
