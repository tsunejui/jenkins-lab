# Project layout

```
jenkins-lab/
├── Dockerfile                  # Custom Jenkins image (plugins pre-installed)
├── docker-compose.yml          # Container definition: ports, volumes, env
├── plugins.txt                 # Jenkins plugins installed at build time
├── mise.toml                   # Tool versions + env for shell/compose/jcasc
├── .gitignore                  # Ignores data/, backups/, exports/, tools/*.jar, …
│
├── jcasc/
│   └── jenkins.yaml            # JCasC main config (admin, security, creds, jobs)
│
├── init.groovy.d/              # Boot-time Groovy hooks (bind-mounted, no rebuild needed)
│   ├── 10-banner.groovy        # Prints a startup banner (demo hook)
│   └── 50-seed-pipelines.groovy# Creates/updates pipeline jobs from pipelines/
│
├── pipelines/                  # One .Jenkinsfile per pipeline job (canonical source)
│   ├── hello-world.Jenkinsfile
│   ├── system-check.Jenkinsfile
│   └── secret-demo.Jenkinsfile
│
├── jobs/                       # (optional) full config.xml for non-pipeline jobs
│
├── justfile                    # Shared variables + imports
├── just.d/                     # Recipes grouped by responsibility
│   ├── lifecycle.just          # [jenkins]      container up/down/logs/clean/reinit
│   ├── cli.just                # [cli]          jenkins-cli wrappers, wait-ready
│   ├── pipeline.just           # [pipeline]     job CRUD, export, j2gitlab, test
│   └── interactive.just        # [interactive]  gum-powered menus & pickers
│
├── scripts/                    # Extracted shell bodies invoked by recipes
│   ├── _lib.sh                 # Helpers: cli(), _jq(), _jcurl(), _when()
│   ├── wait-ready.sh
│   ├── job-apply.sh
│   ├── job-sync.sh
│   ├── pipelines.sh            # list WorkflowJob entries
│   ├── pipeline-info.sh        # static definition view (CLI)
│   ├── pipeline-status.sh      # runtime state view (REST)
│   ├── pipeline-export.sh      # dump config + build artefacts
│   └── pipeline-menu.sh        # interactive pipeline action menu
│
├── tools/                      # Downloaded binaries (git-ignored via tools/*.jar)
│   └── jenkins-cli.jar         # Fetched on first `just cli-jar`
│
├── example/
│   └── j2gitlab/               # Jenkins Pipeline → GitLab CI/CD converter
│       ├── README.md
│       ├── j2gitlab.py
│       └── samples/            # Canonical converter outputs
│           ├── hello-world.gitlab-ci.yml
│           └── secret-demo.gitlab-ci.yml
│
├── test/                       # gitlab-ci-local validation harness
│   ├── README.md
│   ├── run.sh                  # Wired to `just test-gitlab`
│   └── fixtures/
│       └── secret-demo.variables.yml
│
├── docs/                       # This directory
│   ├── structure.md            # ← you are here
│   ├── recipes.md
│   ├── configuration.md
│   ├── pipelines.md
│   ├── operations.md
│   ├── jenkins-cli.md
│   └── test-gitlab-cicd.md
│
├── data/                       # (runtime, git-ignored) persistent /var/jenkins_home
├── backups/                    # (runtime, git-ignored) `just backup` output
└── exports/                    # (runtime, git-ignored) `just pipeline-export` output
```

---

## Directory roles at a glance

| Kind | Path | Git-tracked? | Purpose |
|---|---|---|---|
| Source | `jcasc/`, `pipelines/`, `init.groovy.d/`, `jobs/`, `plugins.txt`, `Dockerfile`, `docker-compose.yml` | ✅ | The declarative definition of this Jenkins instance |
| Tooling | `just.d/`, `scripts/`, `justfile`, `mise.toml` | ✅ | How you interact with the lab |
| Docs | `docs/`, top-level `README.md`, sub-READMEs | ✅ | Reading material |
| Extensions | `example/j2gitlab/`, `test/` | ✅ | Converter tool + tests |
| Runtime state | `data/`, `backups/`, `exports/` | ❌ | Ephemeral / produced by commands |
| Downloaded | `tools/jenkins-cli.jar` | ❌ | Fetched from the running controller |

Anything git-tracked is the real source of truth. Wiping the non-tracked
directories (`just reinit`) reproduces Jenkins state from scratch.
