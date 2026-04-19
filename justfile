set shell := ["bash", "-cu"]

# ─── shared variables ─────────────────────────────────────────────────────────
compose     := "docker compose"
service     := "jenkins"
data_dir    := "./data/jenkins_home"
jobs_dir    := "./jobs"
cli_jar     := "./jenkins-cli.jar"
jenkins_url := env_var_or_default("JENKINS_URL", "http://localhost:8090")
admin_id    := env_var_or_default("JENKINS_ADMIN_ID", "admin")
admin_pw    := env_var_or_default("JENKINS_ADMIN_PASSWORD", "admin")
java        := "mise exec -- java"
gum         := "mise exec -- gum"
cli         := java + " -jar " + cli_jar + " -s " + jenkins_url + " -auth " + admin_id + ":" + admin_pw

# ─── imports ──────────────────────────────────────────────────────────────────
import './just.d/lifecycle.just'
import './just.d/cli.just'
import './just.d/pipeline.just'
import './just.d/interactive.just'

# Show available recipes
default:
    @just --list
