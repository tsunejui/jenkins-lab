# ─── pipeline / job management ────────────────────────────────────────────────
# Convention: each pipeline job lives at {{jobs_dir}}/<NAME>.xml

# List all jobs on the controller (any kind)
[group('pipeline')]
job-list: cli-jar
    @{{cli}} list-jobs

# List pipeline-type jobs only (WorkflowJob), with status + URL
[group('pipeline')]
pipelines:
    @./scripts/pipelines.sh

# Export a pipeline's config + metadata + last-build artefacts into DIR/NAME/
[group('pipeline')]
pipeline-export NAME DIR=exports_dir:
    @./scripts/pipeline-export.sh {{NAME}} {{DIR}}

# Static definition of a pipeline (CLI get-job): description, stages, script
[group('pipeline')]
pipeline-info NAME: cli-jar
    @./scripts/pipeline-info.sh {{NAME}}

# Runtime state of a pipeline build (REST): result, duration, stages, history
[group('pipeline')]
pipeline-status NAME BUILD="lastBuild":
    @./scripts/pipeline-status.sh {{NAME}} {{BUILD}}

# Print a job's config.xml from the controller
[group('pipeline')]
job-get NAME: cli-jar
    @{{cli}} get-job {{NAME}}

# Dump a job's config.xml into jobs/<NAME>.xml (roundtrip helper)
[group('pipeline')]
job-dump NAME: cli-jar
    @mkdir -p {{jobs_dir}}
    @{{cli}} get-job {{NAME}} > {{jobs_dir}}/{{NAME}}.xml
    @echo "Saved → {{jobs_dir}}/{{NAME}}.xml"

# Create job from jobs/<NAME>.xml (fails if job exists)
[group('pipeline')]
job-create NAME: cli-jar
    @test -f {{jobs_dir}}/{{NAME}}.xml || { echo "Missing {{jobs_dir}}/{{NAME}}.xml"; exit 1; }
    @{{cli}} create-job {{NAME}} < {{jobs_dir}}/{{NAME}}.xml
    @echo "Job '{{NAME}}' created → {{jenkins_url}}/job/{{NAME}}/"

# Update an existing job from jobs/<NAME>.xml
[group('pipeline')]
job-update NAME: cli-jar
    @test -f {{jobs_dir}}/{{NAME}}.xml || { echo "Missing {{jobs_dir}}/{{NAME}}.xml"; exit 1; }
    @{{cli}} update-job {{NAME}} < {{jobs_dir}}/{{NAME}}.xml
    @echo "Job '{{NAME}}' updated."

# Create-or-update (idempotent) from jobs/<NAME>.xml
[group('pipeline')]
job-apply NAME: cli-jar
    @./scripts/job-apply.sh {{NAME}}

# Apply every jobs/*.xml to the controller (bulk seed/sync)
[group('pipeline')]
job-sync: cli-jar
    @./scripts/job-sync.sh

# Delete a job (destructive, prompts for confirmation)
[group('pipeline')]
[confirm("Delete job '{{NAME}}'?")]
job-delete NAME: cli-jar
    @{{cli}} delete-job {{NAME}}
    @echo "Job '{{NAME}}' deleted."

# Enable a disabled job
[group('pipeline')]
job-enable NAME: cli-jar
    @{{cli}} enable-job {{NAME}}
    @echo "Job '{{NAME}}' enabled."

# Disable a job
[group('pipeline')]
job-disable NAME: cli-jar
    @{{cli}} disable-job {{NAME}}
    @echo "Job '{{NAME}}' disabled."

# Trigger a build and stream console output (-s wait, -v verbose)
# Pass pipeline parameters via ARGS, e.g. `just job-build my-job -p ENV=prod`
[group('pipeline')]
job-build NAME *ARGS: cli-jar
    @{{cli}} build {{NAME}} -s -v {{ARGS}}

# Show the console log for a given build (default: lastBuild)
[group('pipeline')]
job-log NAME BUILD="lastBuild": cli-jar
    @{{cli}} console {{NAME}} {{BUILD}}

# Summary of the last build (number/result/duration) via REST
[group('pipeline')]
job-last NAME:
    @curl -fsS -u {{admin_id}}:{{admin_pw}} \
        '{{jenkins_url}}/job/{{NAME}}/lastBuild/api/json?tree=number,result,duration,timestamp,url' \
        | python3 -m json.tool

# Open a job's page in the default browser
[group('pipeline')]
job-open NAME:
    @command -v open >/dev/null && open {{jenkins_url}}/job/{{NAME}}/ || xdg-open {{jenkins_url}}/job/{{NAME}}/
