# `just` recipe reference

Run `just` (or `just default`) for the live listing. Recipes are grouped by
responsibility — each group lives in its own `just.d/*.just` file.

---

## `[jenkins]` — container lifecycle (`just.d/lifecycle.just`)

| Command | Purpose |
|---|---|
| `just up` | Build the image if needed and start the container. |
| `just down` | Stop and remove the container; local `data/` stays intact. |
| `just restart` | Restart the running container (re-runs init hooks). |
| `just status` | `docker compose ps` for the service. |
| `just logs` | Follow the last 200 lines of controller logs (`Ctrl+C` exits). |
| `just shell` | Drop into the container's bash. |
| `just version` | Print the Jenkins version via `java -jar jenkins.war --version`. |
| `just open` | Open `http://localhost:8090` in the default browser. |
| `just init` | Make sure `./data/jenkins_home` exists (called by `up`). |
| `just pull` | `compose pull` (base image layers). |
| `just upgrade` | `compose build --pull` + `compose up -d --force-recreate`. |
| `just backup` | Tar the volume into `backups/jenkins_home-<timestamp>.tar.gz`. |
| `just clean` | Down + remove `./data/jenkins_home` (confirm). |
| `just reinit` | Full reset: `clean` → rebuild → start fresh (confirm). |

---

## `[cli]` — Jenkins CLI helpers (`just.d/cli.just`)

| Command | Purpose |
|---|---|
| `just wait-ready` | Poll `http://…/login` until HTTP 200 (gum spinner). |
| `just cli-jar` | Download `jenkins-cli.jar` into `tools/` (cached). |
| `just cli-jar-refresh` | Remove and re-download after a Jenkins upgrade. |
| `just cli <args>` | Run any CLI subcommand, e.g. `just cli help`, `just cli list-jobs`. |
| `just reload-casc` | Re-apply JCasC (`apply-configuration` under the hood). |

See [`docs/jenkins-cli.md`](jenkins-cli.md) for auth options, cheatsheet,
and direct invocation outside `just`.

---

## `[pipeline]` — job CRUD and analysis (`just.d/pipeline.just`)

### Listing / inspecting
| Command | Purpose |
|---|---|
| `just job-list` | List every job (any kind). |
| `just pipelines` | List WorkflowJob entries with status + URL. |
| `just pipeline-info <NAME>` | Static definition view (CLI `get-job`): description, stage labels, script pointers. |
| `just pipeline-status <NAME> [BUILD]` | Runtime view (REST): result, duration, stage timing, recent history. |
| `just job-get <NAME>` | Raw `config.xml` from the controller. |

### CRUD from local files
Convention: full XML → `jobs/<NAME>.xml`; pipeline script only → `pipelines/<NAME>.Jenkinsfile`.

| Command | Purpose |
|---|---|
| `just job-apply <NAME>` | Idempotent **create-or-update** from `jobs/<NAME>.xml`. |
| `just job-create <NAME>` | Strict create (fails if exists). |
| `just job-update <NAME>` | Strict update (fails if missing). |
| `just job-sync` | Bulk apply every `jobs/*.xml`. |
| `just job-dump <NAME>` | Save controller-side config back to `jobs/<NAME>.xml`. |
| `just job-delete <NAME>` | Delete, with confirmation prompt. |

### Build control
| Command | Purpose |
|---|---|
| `just job-build <NAME> [-p KEY=VAL]` | Trigger + stream console; params via `-p`. |
| `just job-log <NAME> [BUILD]` | Console log for a build (default `lastBuild`). |
| `just job-last <NAME>` | Last-build JSON summary via REST. |
| `just job-enable <NAME>` / `just job-disable <NAME>` | Toggle build eligibility. |
| `just job-open <NAME>` | Open the job page in the browser. |

### Export + convert + test
| Command | Purpose |
|---|---|
| `just pipeline-export <NAME> [DIR]` | Dump `config.xml` / `info.json` / `stages.json` / `last-build.json` / `console.log` to `DIR/NAME/` (default `./exports/`). |
| `just j2gitlab <NAME> [DIR]` | Convert pipeline → `.gitlab-ci.yml` on stdout. Details: [`example/j2gitlab/README.md`](../example/j2gitlab/README.md). |
| `just test-gitlab` | Validate + run every generated sample with `gitlab-ci-local`. Details: [`test/README.md`](../test/README.md). |

---

## `[interactive]` — gum-powered menus (`just.d/interactive.just`)

| Command | Purpose |
|---|---|
| `just pipeline` | Two-level menu: choose action → choose job. |
| `just build-i` | Pick a job interactively, then trigger it. |
| `just log-i` | Pick a job interactively, then show its last log. |
| `just apply-i` | Pick a local XML interactively, then apply it. |
| `just pick-job` | Interactive picker that emits the chosen job name (composable). |
| `just pick-local` | Interactive picker over `jobs/*.xml` (composable). |

All interactive recipes need a real TTY. `pick-*` helpers are designed to
work inside shell pipelines, e.g. `just pick-job | xargs -I{} just job-log {}`.

---

## End-to-end sequence

```bash
just up                           # Jenkins up, pipelines seeded
just wait-ready
just job-build hello-world        # run the pipeline
just pipeline-export hello-world  # dump to exports/hello-world/
just j2gitlab hello-world > example/j2gitlab/samples/hello-world.gitlab-ci.yml
just test-gitlab                  # verify conversion via gitlab-ci-local
```

Full walkthrough with diagrams in
[`docs/test-gitlab-cicd.md`](test-gitlab-cicd.md).
