# ─── pipeline / job management ────────────────────────────────────────────────
# Convention: each pipeline job lives at {{jobs_dir}}/<NAME>.xml

# List all jobs on the controller (any kind)
[group('pipeline')]
job-list: cli-jar
    @{{cli}} list-jobs

# List pipeline-type jobs only (WorkflowJob), with status + URL
[group('pipeline')]
pipelines:
    #!/usr/bin/env python3
    import json, urllib.request, base64, sys
    URL = "{{jenkins_url}}/api/json?tree=jobs[name,_class,color,url]"
    AUTH = base64.b64encode(b"{{admin_id}}:{{admin_pw}}").decode()
    req = urllib.request.Request(URL, headers={"Authorization": f"Basic {AUTH}"})
    try:
        data = json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        print(f"query failed: {e}", file=sys.stderr); sys.exit(1)
    rows = [j for j in data.get("jobs", []) if j["_class"].endswith("WorkflowJob")]
    if not rows:
        print("(no pipeline jobs)"); sys.exit(0)
    STATUS = {"blue": "SUCCESS", "red": "FAILED", "yellow": "UNSTABLE",
              "aborted": "ABORTED", "disabled": "DISABLED", "notbuilt": "NEVER_RUN"}
    nw = max(len(j["name"]) for j in rows)
    print(f"{'NAME':<{nw}}  {'STATUS':<18}  URL")
    print("-" * (nw + 2 + 18 + 2 + 40))
    for j in rows:
        color = j.get("color") or "notbuilt"
        running = color.endswith("_anime")
        base = color.replace("_anime", "")
        status = STATUS.get(base, base.upper())
        if running: status += " (running)"
        print(f"{j['name']:<{nw}}  {status:<18}  {j['url']}")

# Full summary of a single pipeline: metadata + last build + stages + history
[group('pipeline')]
pipeline-info NAME:
    #!/usr/bin/env python3
    import json, urllib.request, base64, datetime, sys
    BASE = "{{jenkins_url}}"
    NAME = "{{NAME}}"
    AUTH = base64.b64encode(b"{{admin_id}}:{{admin_pw}}").decode()

    def get(path):
        req = urllib.request.Request(f"{BASE}{path}",
                                     headers={"Authorization": f"Basic {AUTH}"})
        return json.loads(urllib.request.urlopen(req, timeout=10).read())

    def when(ms):
        return datetime.datetime.fromtimestamp(ms / 1000).isoformat(timespec="seconds")

    try:
        job = get(f"/job/{NAME}/api/json?tree=name,_class,description,"
                  f"buildable,disabled,nextBuildNumber,url,color,"
                  f"lastBuild[number,result,duration,timestamp,url],"
                  f"builds[number,result,duration,timestamp]")
    except Exception as e:
        print(f"cannot fetch job '{NAME}': {e}", file=sys.stderr); sys.exit(1)

    print(f"Name          : {job['name']}")
    print(f"Class         : {job['_class'].rsplit('.', 1)[-1]}")
    print(f"URL           : {job['url']}")
    if job.get("description"):
        print(f"Description   : {job['description']}")
    print(f"Buildable     : {job.get('buildable')}")
    if job.get("disabled"):
        print("Disabled      : True")
    print(f"Next build #  : {job.get('nextBuildNumber')}")
    print(f"Color         : {job.get('color')}")

    lb = job.get("lastBuild")
    if not lb:
        print("\n(no builds yet)"); sys.exit(0)

    print(f"\nLast build    : #{lb['number']} "
          f"{lb.get('result') or 'RUNNING'}  "
          f"duration={lb['duration']}ms  at {when(lb['timestamp'])}")
    print(f"                {lb['url']}")

    try:
        wf = get(f"/job/{NAME}/lastBuild/wfapi/describe")
        print("\nStages (last build):")
        for s in wf.get("stages", []):
            print(f"  {s['name']:<18} {s['status']:<10} {s['durationMillis']:>6}ms")
    except Exception as e:
        print(f"\n(stage info unavailable: {e})")

    builds = (job.get("builds") or [])[:8]
    if builds:
        print("\nRecent builds:")
        for b in builds:
            print(f"  #{b['number']:<4} {(b.get('result') or 'RUNNING'):<8} "
                  f"{b['duration']:>6}ms  {when(b['timestamp'])}")

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
    @test -f {{jobs_dir}}/{{NAME}}.xml || { echo "Missing {{jobs_dir}}/{{NAME}}.xml"; exit 1; }
    @if {{cli}} list-jobs 2>/dev/null | grep -qxF "{{NAME}}"; then \
        {{cli}} update-job {{NAME}} < {{jobs_dir}}/{{NAME}}.xml && echo "Job '{{NAME}}' updated."; \
    else \
        {{cli}} create-job {{NAME}} < {{jobs_dir}}/{{NAME}}.xml && echo "Job '{{NAME}}' created."; \
    fi

# Apply every jobs/*.xml to the controller (bulk seed/sync)
[group('pipeline')]
job-sync: cli-jar
    @shopt -s nullglob; \
    existing="$({{cli}} list-jobs 2>/dev/null)"; \
    for f in {{jobs_dir}}/*.xml; do \
        n=$(basename "$f" .xml); \
        if echo "$existing" | grep -qxF "$n"; then \
            {{cli}} update-job "$n" < "$f" && echo "updated : $n"; \
        else \
            {{cli}} create-job "$n" < "$f" && echo "created : $n"; \
        fi; \
    done

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
