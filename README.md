# Jenkins Lab

A reproducible Jenkins sandbox built with Docker Compose + JCasC, driven by
a `just` + `gum` CLI. Includes a Jenkins Pipeline → GitLab CI/CD converter and
a local `gitlab-ci-local` harness for validating the converted output.

---

## Architecture

```
                        Host (this repo)                          Docker container
 ┌────────────────────────────────────────────────┐   ┌──────────────────────────────────────┐
 │                                                │   │  jenkins-lab (jenkins/jenkins:lts)   │
 │  ── source (git-tracked) ─────────────────┐    │   │                                      │
 │  │ jcasc/jenkins.yaml                     │────┼───┼─▶ /var/jenkins_jcasc/jenkins.yaml    │
 │  │ pipelines/*.Jenkinsfile                │────┼───┼─▶ /var/jenkins_pipelines/            │
 │  │ init.groovy.d/*.groovy                 │────┼───┼─▶ /var/jenkins_home/init.groovy.d    │
 │  │ Dockerfile + plugins.txt               │ (baked into image layer)                      │
 │  └────────────────────────────────────────┘    │   │                                      │
 │                                                │   │  ┌────────────────────────────────┐  │
 │  ── runtime (gitignored) ─────────────────┐    │   │  │ Jenkins core + JCasC plugin    │  │
 │  │ data/jenkins_home                      │◀───┼───┼──│  • admin user from mise env    │  │
 │  │   (jobs / credentials / build history) │    │   │  │  • credentials via JCasC       │  │
 │  └────────────────────────────────────────┘    │   │  │  • seeded pipelines via hook   │  │
 │                                                │   │  └────────────────────────────────┘  │
 │  ── tooling (host-side) ──────────────────┐    │HTTP│                 ▲                    │
 │  │ just + scripts/*.sh                    │────┼────┼─ :8090  UI      │                    │
 │  │ tools/jenkins-cli.jar (downloaded)     │────┼────┼─ :8090  CLI / REST                   │
 │  │ example/j2gitlab/j2gitlab.py           │    │    │  :50000 agent inbound                │
 │  │ test/run.sh  (gitlab-ci-local)         │    │    │                                      │
 │  └────────────────────────────────────────┘    │    └──────────────────────────────────────┘
 └────────────────────────────────────────────────┘
            ▲
   mise env (JENKINS_URL, admin id/pw, DEMO_*) propagates into every layer
```

**Key idea** — every piece of Jenkins state is declared on the host and
projected into the container via bind mounts or JCasC substitution. The
container holds only runtime data; nuking it and re-running `just up`
reproduces the same Jenkins bit-for-bit.

---

## Workflow

From editing a `Jenkinsfile` to a validated GitLab CI/CD YAML:

```
  pipelines/<name>.Jenkinsfile                  ◀─ source of truth (git)
          │
          │  (1) just up                        — boot; init.groovy.d seeds jobs
          ▼
  Jenkins WorkflowJob  (controller)
          │
          │  (2) just job-build <name>          — trigger + stream console
          ▼
  Build history + artefacts on controller       ─── just pipeline-status <name>
          │                                         (live REST view)
          │  (3) just pipeline-export <name>    — dump controller state to local files
          ▼
  exports/<name>/
   ├─ config.xml         ← pipeline definition (used by the converter)
   ├─ info.json / stages.json / last-build.json
   └─ console.log
          │
          │  (4) just j2gitlab <name>           — Declarative Pipeline → .gitlab-ci.yml
          ▼
  example/j2gitlab/samples/<name>.gitlab-ci.yml
          │
          │  (5) just test-gitlab               — parse + run via gitlab-ci-local
          ▼
  PASS / FAIL   (no GitLab server required)
```

Full step-by-step with commands and file artefacts in
[`docs/test-gitlab-cicd.md`](docs/test-gitlab-cicd.md).

---

## Quick start

```bash
just init                       # mise install + link dev env + mkdir data (once)
just up                         # build image, start container, load JCasC
just wait-ready                 # block until http://localhost:8090/login is 200
just job-build hello-world      # run the demo pipeline (seeded automatically)
just test-gitlab                # convert + validate the GitLab CI sample
```

Default credentials for the seeded local Jenkins: `admin` / `admin`
(defined in `jenkins-envs/dev.toml`; switch or override as shown below).

---

## Multi-environment setup

Per-environment values (`JENKINS_URL`, admin credentials, demo secrets) live
under [`jenkins-envs/`](jenkins-envs/) — one `.toml` per target:

```
jenkins-envs/
├── dev.toml              # git-tracked default: local docker Jenkins
├── staging.toml          # you add these as you need them
└── prod.toml             # …
```

`just init` symlinks `.mise.local.toml → jenkins-envs/dev.toml` on first run
(`.mise.local.toml` itself is `.gitignore`d, so each machine picks its own
target). `mise` merges the linked file's `[env]` over `mise.toml`.

### Switch target interactively

```bash
just jenkins-envs
# ? Select Jenkins env   (current: dev)
#   › dev
#     staging
#     prod
```

Picks any `*.toml` under `jenkins-envs/`, updates the symlink, and prints a
preview (passwords / tokens masked).

### Add a new target

```bash
cat > jenkins-envs/staging.toml <<'TOML'
[env]
JENKINS_URL            = "https://jenkins.staging.example.com"
JENKINS_ADMIN_ID       = "rex"
JENKINS_ADMIN_PASSWORD = "<api-token-from-Jenkins-UI>"

# Only needed if secret-demo is on that controller:
DEMO_API_TOKEN     = "…"
DEMO_USER_ID       = "…"
DEMO_USER_PASSWORD = "…"
TOML

just jenkins-envs          # pick "staging"
just cli who-am-i          # verify auth against the remote controller
```

**Only non-`[jenkins]` recipes** (i.e. `[cli]`, `[pipeline]`, `[interactive]`)
target the linked Jenkins. `just up` / `down` / `restart` etc. always act on
the **local** container, regardless of which env file is linked.

See [`docs/configuration.md`](docs/configuration.md) for credential rotation,
API-token setup, and machine-local overrides.

---

## Documentation

| Topic | Doc |
|---|---|
| Project layout | [`docs/structure.md`](docs/structure.md) |
| `just` recipe reference (all groups, every command) | [`docs/recipes.md`](docs/recipes.md) |
| JCasC, credentials, env, re-initialising | [`docs/configuration.md`](docs/configuration.md) |
| Creating / managing pipelines, using secrets | [`docs/pipelines.md`](docs/pipelines.md) |
| Jenkins CLI — how the jar is obtained & used | [`docs/jenkins-cli.md`](docs/jenkins-cli.md) |
| End-to-end Jenkins → GitLab CI test flow | [`docs/test-gitlab-cicd.md`](docs/test-gitlab-cicd.md) |
| Operations: troubleshooting, extending | [`docs/operations.md`](docs/operations.md) |
| Jenkins Pipeline → GitLab CI converter | [`example/j2gitlab/README.md`](example/j2gitlab/README.md) |
| `gitlab-ci-local` harness | [`test/README.md`](test/README.md) |

---

## Prerequisites

- Docker (Docker Desktop / Rancher Desktop / OrbStack all work)
- [mise](https://mise.jdx.dev) — tool versions pinned in `mise.toml`
- Shell with mise activation (e.g. `eval "$(mise activate zsh)"`)

Repo is public on GitHub: <https://github.com/tsunejui/jenkins-lab>
