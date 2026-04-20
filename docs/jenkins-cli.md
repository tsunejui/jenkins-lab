# Jenkins CLI (`jenkins-cli.jar`)

The [Jenkins CLI](https://www.jenkins.io/doc/book/managing/cli/) is a thin Java
client that talks to a running controller over HTTP. This lab drives every
job-management operation through it so that pipelines stay reproducible and
can be applied from source control.

This document explains how the jar is obtained and how to use it — both via
the `just` recipes that ship with the repo and directly on the command line.

---

## Where the jar lives

```
jenkins-lab/
└── tools/
    └── jenkins-cli.jar   # downloaded on demand, git-ignored
```

- The path is exposed to recipes as `{{cli_jar}}` (`./tools/jenkins-cli.jar`).
- `tools/*.jar` is listed in `.gitignore`, so the binary never gets committed.
- The jar is **version-coupled** to the running controller — always grab it
  from your own instance instead of redistributing a copy.

---

## Getting the jar

### 1. Via `just` (recommended)

```bash
just cli-jar             # downloads to tools/jenkins-cli.jar if missing
just cli-jar-refresh     # delete + redownload (run this after upgrading Jenkins)
```

Both recipes implicitly depend on `wait-ready`, so they block until the
controller responds on `/login`.

### 2. Manual download

```bash
mkdir -p tools
curl -fsSo tools/jenkins-cli.jar http://localhost:8090/jnlpJars/jenkins-cli.jar
```

Any reachable Jenkins URL works — `/jnlpJars/jenkins-cli.jar` is served by
the controller itself.

### 3. From inside the container

```bash
docker cp jenkins-lab:/usr/share/jenkins/jenkins.war - \
  | tar -x --to-stdout WEB-INF/lib/cli-*.jar > tools/jenkins-cli.jar
```

Useful when the controller isn't exposed to the host network.

---

## Running the jar

### Requirements

- **Java 21+** — the CLI jar is compiled for the controller's JVM, so an
  older host JDK will fail with `UnsupportedClassVersionError`.
- This repo uses `mise exec -- java` in every recipe to guarantee Temurin 21
  is used regardless of the caller's shell.

### Generic shape

```bash
java -jar tools/jenkins-cli.jar \
     -s  <controller-url> \
     -auth <user>:<password-or-token> \
     <command> [args…]
```

### Authentication options

| Flag / env | Format | Notes |
|---|---|---|
| `-auth user:pass` | username + password **or** API token | Simplest; what this lab uses |
| `-auth @path` | File containing `user:secret` | Keeps secrets out of process args |
| `JENKINS_USER_ID` + `JENKINS_API_TOKEN` | Env vars | Picked up automatically when `-auth` is omitted |

For CI, prefer API tokens over passwords (Jenkins → *Your user → Configure →
API Token → Add new token*).

---

## `just` wrappers

Every CLI operation has a matching `just` recipe, so you rarely need to type
the full `java -jar …` command.

| `just` recipe | Underlying CLI command |
|---|---|
| `just cli <args>` | passthrough to `jenkins-cli.jar` |
| `just job-list` | `list-jobs` |
| `just pipelines` | REST `/api/json` filtered to `WorkflowJob` |
| `just pipeline-info NAME` | REST `/job/NAME/api/json` + `/wfapi/describe` composed |
| `just job-get NAME` | `get-job NAME` |
| `just job-create NAME` | `create-job NAME < jobs/NAME.xml` |
| `just job-update NAME` | `update-job NAME < jobs/NAME.xml` |
| `just job-apply NAME` | `create-job` or `update-job` depending on existence |
| `just job-delete NAME` | `delete-job NAME` |
| `just job-build NAME` | `build NAME -s -v` |
| `just job-log NAME [BUILD]` | `console NAME BUILD` |
| `just reload-casc` | `reload-configuration-as-code` |

Credentials (`JENKINS_ADMIN_ID` / `JENKINS_ADMIN_PASSWORD`) come from
`mise.toml` `[env]`, so recipes always have the right `-auth` string.

---

## Direct usage cheatsheet

All examples assume the jar is downloaded and `JENKINS_URL`, `JENKINS_ADMIN_ID`,
and `JENKINS_ADMIN_PASSWORD` are exported (mise handles this automatically).

```bash
alias jcli='mise exec -- java -jar tools/jenkins-cli.jar \
  -s "$JENKINS_URL" -auth "$JENKINS_ADMIN_ID:$JENKINS_ADMIN_PASSWORD"'

# Discovery
jcli help                                 # list all commands
jcli help build                           # help for a single command
jcli who-am-i                             # verify auth
jcli version                              # controller version

# Job management
jcli list-jobs
jcli get-job hello-world > hello.xml
jcli create-job my-pipeline  < my-pipeline.xml
jcli update-job my-pipeline  < my-pipeline.xml
jcli delete-job my-pipeline

# Running builds
jcli build hello-world -s -v              # wait (-s) + stream console (-v)
jcli build hello-world -p GIT_REF=main    # pass a pipeline parameter
jcli console hello-world                  # log of lastBuild
jcli console hello-world 3                # log of build #3
jcli stop-builds hello-world              # abort running builds

# Nodes / agents
jcli list-nodes
jcli online-node built-in
jcli offline-node built-in -m "upgrade"

# Configuration as Code
jcli reload-configuration-as-code
jcli export-configuration-as-code > jcasc/dump.yaml

# Plugins
jcli list-plugins
jcli install-plugin pipeline-utility-steps

# Scripting (Groovy console over CLI)
echo 'println(Jenkins.instance.version)' | jcli groovy =
```

See `jcli help` for the full command list (the controller exposes
~40 commands, varying slightly by plugin set).

---

## Notes & gotchas

- **SSH transport** (`-ssh -user …`) exists but is disabled by default in
  recent releases; HTTP + `-auth` is the supported path.
- The CLI requires CSRF crumb handling only for certain commands; the jar
  negotiates this for you transparently.
- Long-lived streaming commands (`build -s -v`, `console -f`) block until the
  build finishes — wrap them in `timeout` if you need bounded runs.
- If a command hangs, verify reachability with `curl -I "$JENKINS_URL/login"`;
  the CLI surfaces network errors only after a retry window.
- After a major Jenkins upgrade, always `just cli-jar-refresh` so the jar
  matches the new controller.

---

## References

- Jenkins CLI overview — <https://www.jenkins.io/doc/book/managing/cli/>
- Declarative Pipeline syntax — <https://www.jenkins.io/doc/book/pipeline/syntax/>
- Configuration as Code — <https://github.com/jenkinsci/configuration-as-code-plugin>
