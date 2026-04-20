# Jenkins Lab

A reproducible Jenkins sandbox built with Docker Compose + JCasC, driven by
an interactive `just` + `gum` CLI for pipeline management.

---

## Layout

```
jenkins-lab/
├── Dockerfile              # Custom image: jenkins-plugin-cli + init hooks
├── docker-compose.yml      # Service definition: ports, volumes, env
├── plugins.txt             # Plugins required by JCasC / Pipeline / Git
├── jcasc/
│   └── jenkins.yaml        # JCasC main config (admin, security, location)
├── init.groovy.d/
│   ├── 10-banner.groovy         # Example Groovy boot hook
│   └── 50-seed-pipelines.groovy # Auto-creates pipelines from *.Jenkinsfile
├── pipelines/
│   ├── hello-world.Jenkinsfile  # Canonical pipeline, seeded on boot
│   ├── system-check.Jenkinsfile # Demo of multi-file seeding
│   └── secret-demo.Jenkinsfile  # Consumes credentials via withCredentials
├── jobs/                         # (optional) full config.xml for non-pipeline jobs
├── tools/                  # Binary artefacts (jenkins-cli.jar), git-ignored
├── docs/
│   └── jenkins-cli.md      # How to obtain and use jenkins-cli.jar
├── mise.toml               # Tool versions (just / java / gum) + env
├── justfile                # Shared variables + imports
├── just.d/
│   ├── lifecycle.just      # [jenkins]      container lifecycle
│   ├── cli.just            # [cli]          jenkins-cli wrappers
│   ├── pipeline.just       # [pipeline]     job-* management
│   └── interactive.just    # [interactive]  gum-powered menus
└── scripts/                # Extracted shell bodies invoked by the recipes
    ├── _lib.sh             # Shared helpers: cli(), _jq(), _jcurl(), _when()
    ├── wait-ready.sh
    ├── job-apply.sh
    ├── job-sync.sh
    ├── pipelines.sh
    ├── pipeline-info.sh
    ├── pipeline-status.sh
    ├── pipeline-export.sh
    └── pipeline-menu.sh
```

Runtime state persists at `./data/jenkins_home`, backups at `./backups/` —
both are `.gitignore`d.

---

## Prerequisites

- Docker (Desktop / Rancher Desktop / OrbStack all work)
- [mise](https://mise.jdx.dev) — installs `just`, `java@21`, `gum` pinned in `mise.toml`
- A shell that activates mise (e.g. `eval "$(mise activate zsh)"`)

First clone:

```bash
mise trust           # trust mise.toml
mise install         # install just / temurin-21 / gum
```

---

## Quick start

```bash
just up                        # build image, start container, load JCasC
just wait-ready                # poll until http://localhost:8090/login is 200
just job-apply hello-world     # create pipeline via Jenkins CLI
just job-build hello-world     # trigger and stream console output
just job-last hello-world      # inspect the last build summary
just open                      # open the UI in the browser
```

Default credentials: `admin` / `admin` (override in `mise.toml`).

---

## How it works

```
┌───────────┐   mise env   ┌────────────────┐  ${VAR}  ┌─────────────────┐
│ mise.toml │─────────────▶│ docker-compose │─────────▶│ jcasc/jenkins.yml│──┐
└───────────┘              └────────────────┘          └─────────────────┘  │
                                                                             ▼
                                                      Jenkins boots, JCasC creates admin
                                                                             │
                    ┌────────────────────────────────────────────────────────┘
                    ▼
            ┌──────────────┐  CLI + XML  ┌──────────────┐
            │ just job-*   │────────────▶│ Pipeline job │
            └──────────────┘             └──────────────┘
```

1. **`mise.toml`** holds the credentials + URL. They are exported to the shell
   automatically when entering the project directory.
2. **`docker-compose.yml`** reads those env vars, starts the container, and
   mounts `./jcasc` into `/var/jenkins_jcasc`.
3. **`CASC_JENKINS_CONFIG`** points at the yaml; JCasC creates the admin user
   and disables the setup wizard on boot.
4. **`just job-*`** drives `jenkins-cli.jar` over REST/CLI, treating
   `jobs/*.xml` as the source of truth.

---

## `just` command reference

Run `just` (or `just default`) for the full list. Recipes are grouped:

### `[jenkins]` — container lifecycle
| Command | Purpose |
|---|---|
| `just up` | Build the image and start the container |
| `just down` | Stop and remove the container (data persists) |
| `just restart` / `status` / `logs` | Restart / status / tail logs |
| `just shell` | Drop into the container's bash |
| `just version` | Print the Jenkins version |
| `just upgrade` | Pull the latest base image and recreate |
| `just backup` | Archive `jenkins_home` into `backups/` |
| `just clean` | Destroy the container and local data (confirm required) |

### `[cli]` — jenkins-cli helpers
| Command | Purpose |
|---|---|
| `just wait-ready` | Wait until `/login` responds (gum spinner) |
| `just cli-jar` | Download `jenkins-cli.jar` into `tools/` (cached) |
| `just cli-jar-refresh` | Re-download after a Jenkins upgrade |
| `just cli <args>` | Run any CLI subcommand, e.g. `just cli help` |
| `just reload-casc` | Hot-reload JCasC without restarting the container |

See [`docs/jenkins-cli.md`](docs/jenkins-cli.md) for a full walkthrough of
how the CLI is fetched, authenticated, and invoked directly.

### `[pipeline]` — job CRUD
Convention: each job lives at `jobs/<NAME>.xml`.

| Command | Purpose |
|---|---|
| `just job-list` | List every job (any kind) |
| `just pipelines` | List Pipeline-type jobs with status + URL |
| `just pipeline-info <NAME>` | Static definition (CLI `get-job`): description, declared stages, script links |
| `just pipeline-status <NAME> [BUILD]` | Runtime state of a build (REST): result, duration, stages, recent history |
| `just pipeline-export <NAME> [DIR]` | Dump config.xml / info.json / stages / console to `DIR/NAME/` (default `./exports/`) |
| `just j2gitlab <NAME> [DIR]` | Best-effort convert pipeline to GitLab CI/CD YAML (output to stdout) — see [`example/j2gitlab/`](example/j2gitlab/README.md) |
| `just test-gitlab` | Validate + run the generated samples via gitlab-ci-local — see [`test/`](test/README.md) |
| `just job-apply <NAME>` | Idempotent **create-or-update** from local XML |
| `just job-create <NAME>` / `job-update <NAME>` | Strict create / update |
| `just job-sync` | Bulk-apply every `jobs/*.xml` |
| `just job-build <NAME> [-p KEY=VAL]` | Trigger a build and stream output |
| `just job-log <NAME> [BUILD]` | Show a build's console log |
| `just job-last <NAME>` | Print last-build JSON summary via REST |
| `just job-dump <NAME>` | Export the controller-side job back to `jobs/<NAME>.xml` |
| `just job-enable / disable / delete <NAME>` | Toggle state / delete |
| `just job-open <NAME>` | Open the job page in the browser |

### `[interactive]` — gum menus
| Command | Purpose |
|---|---|
| `just pipeline` | Two-level interactive menu: action × job |
| `just build-i` / `log-i` / `apply-i` | Interactive versions of common actions |
| `just pick-job` / `pick-local` | Emit the selected job name — composable in pipelines |

---

## Re-initializing

Pick the right level based on what changed:

| Change | Command | Rationale |
|---|---|---|
| `pipelines/*.Jenkinsfile`, `jcasc/jenkins.yaml`, `init.groovy.d/*.groovy` | `just restart` | Bind-mounted; the container re-reads the files on boot. For JCasC alone, `just reload-casc` hot-reloads without restart. |
| `plugins.txt`, `Dockerfile` | `just upgrade` | Rebuilds the image (pulls base) and recreates the container; local `data/` is preserved. |
| Wants a clean slate (forgot admin password, bcrypt hash mismatch, corrupt state) | `just reinit` | Destroys container + wipes `./data/jenkins_home` + rebuilds + starts fresh. Prompts for confirmation. |

`init.groovy.d/` used to be baked into the image (and therefore ignored after
the first boot). It is now bind-mounted at runtime, so `just restart` is
enough for any Groovy hook edit.

---

## Editing JCasC

1. Edit `jcasc/jenkins.yaml`
2. Run `just reload-casc` (hot reload) or `just restart`
3. A misconfigured yaml triggers `BootFailure` on startup; check
   `just logs` for the precise exception

Adding users / changing authorization: tweak `securityRealm` and
`authorizationStrategy`. New plugin dependencies: append to `plugins.txt` →
`just build` → `just restart`.

---

## Adding a pipeline

Two supported patterns:

### A. Jenkinsfile + boot-time seed (recommended)

Drop a `<name>.Jenkinsfile` under `./pipelines/`. On every container start,
`init.groovy.d/50-seed-pipelines.groovy` reads the directory and
create-or-updates each corresponding `WorkflowJob`.

```bash
# 1. Write the pipeline script
cat > pipelines/my-pipeline.Jenkinsfile <<'EOF'
pipeline {
    agent any
    stages {
        stage('Hello') { steps { echo 'hi' } }
    }
}
EOF

# 2. Apply — restart container so the init hook picks it up
just restart

# 3. Run
just job-build my-pipeline
```

Pros: pipeline script stays as first-class Groovy (syntax-highlighted,
diff-able), no XML boilerplate. Re-applied automatically on every boot, so
manual UI edits are treated as ephemeral.

### B. Full config.xml via Jenkins CLI

When you need more than just the pipeline script (triggers, parameters,
non-pipeline job types), write a complete config under `jobs/<name>.xml`
and push it via CLI.

```bash
cp jobs/example.xml jobs/my-pipeline.xml
vim jobs/my-pipeline.xml
just job-apply my-pipeline
just job-build my-pipeline
```

Or interactively: `just pipeline` → `apply` → pick file → `build`.

---

## Using secrets in pipelines

Credentials are defined declaratively in `jcasc/jenkins.yaml`
(`credentials:` block) and created on every controller boot. Each
credential has an `id` that Jenkinsfiles reference via `withCredentials`:

```groovy
// pipelines/secret-demo.Jenkinsfile (excerpt)
withCredentials([string(credentialsId: 'demo-api-token',
                        variable: 'API_TOKEN')]) {
    sh 'curl -H "Authorization: Bearer $API_TOKEN" https://example.com/api'
}
```

Jenkins automatically masks the bound values as `****` in the console
log — even when a step deliberately tries to print them. The
underlying HTTP response body is not masked, so API calls that echo
the secret back (like `httpbin.org/bearer`) will appear sanitised in
the log because Jenkins replaces the literal string wherever it
appears.

Two demo credentials ship with the lab (see `jcasc/jenkins.yaml`):

| ID | Type | Default value |
|---|---|---|
| `demo-api-token` | Secret text | `$DEMO_API_TOKEN` (falls back to `lab-api-token-change-me`) |
| `demo-basic-auth` | Username + password | `$DEMO_USER_ID` / `$DEMO_USER_PASSWORD` |

Override any of them by setting the env var before `just restart` /
`just reload-casc`. For realistic secrets, prefer `.mise.local.toml`
(git-ignored) over committing values to `mise.toml`.

Run `just job-build secret-demo` to see masking in action.

---

## Credentials & environment

All secrets flow through `mise.toml` `[env]`:

```toml
[env]
JENKINS_URL            = "http://localhost:8090"
JENKINS_ADMIN_ID       = "admin"
JENKINS_ADMIN_PASSWORD = "admin"
```

- mise exports these when you `cd` into the project
- `docker-compose.yml` passes them to the container via `${VAR:-default}`
- `jcasc/jenkins.yaml` substitutes `${VAR}` to create the admin account
- `justfile` reads the same variables via `env_var_or_default` for CLI auth

To change the password:

```bash
# Edit JENKINS_ADMIN_PASSWORD in mise.toml
just clean && just up          # wipe the bcrypt hash and re-provision
# or keep existing data
just restart && just reload-casc
```

Keep local-only overrides in `.mise.local.toml` (already `.gitignore`d).

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Port 8090 is busy | `lsof -iTCP:8090 -sTCP:LISTEN`; change the host port in `docker-compose.yml` |
| CasC `BootFailure: UnknownAttributesException` | The referenced plugin isn't installed — add it to `plugins.txt` and rebuild, or drop that field from the yaml |
| `just cli` emits `UnsupportedClassVersionError` | Host Java is too old; `mise install` ensures Java 21, and recipes invoke `mise exec -- java` |
| Pipeline compile error (`Invalid option "timestamps"`) | Needs the `timestamper` plugin — add it to `plugins.txt` or remove the option |
| Forgot admin password | `just clean` (easiest) or `just shell` and delete `users/admin_*` |

---

## Extending

- Add a new just group: drop a file into `just.d/`, then add one `import` line to `justfile`
- Add a build agent: wire another service into `docker-compose.yml` and have it connect back on port 50000
- Manage secrets: use the Jenkins Credentials plugin plus a `credentials:` block in JCasC
