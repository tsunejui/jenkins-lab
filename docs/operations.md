# Operations: troubleshooting & extending

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Port 8090 is busy on `just up` | `lsof -iTCP:8090 -sTCP:LISTEN`; change the host port in `docker-compose.yml` `ports:`. |
| JCasC `BootFailure: UnknownAttributesException` | The referenced config key doesn't exist in the installed plugin's schema. Add the plugin to `plugins.txt` (and `just upgrade`), or drop the unknown field from the yaml. |
| `just cli` → `UnsupportedClassVersionError` | Host Java is older than what the CLI jar was compiled against. The recipes invoke `mise exec -- java`; run `mise install` to get Temurin 21. |
| Pipeline compile error (`Invalid option "timestamps"`) | Depends on the `timestamper` plugin. Add it to `plugins.txt` + `just upgrade`, or remove the option from the Jenkinsfile. |
| Forgot admin password | Easiest: `just reinit` (wipes data, re-provisions from JCasC). Alternative: `just shell` and delete `/var/jenkins_home/users/admin_*/`. |
| `just pipeline-export X` fails on `lastBuild.number // empty` | The job has never run. Trigger once with `just job-build X`, then retry the export. |
| `just j2gitlab` output truncates at a `#` in an echo line | YAML plain-scalar comment rule — already fixed by routing echo/sh through `yaml_inline`. Regenerate the sample with the latest `j2gitlab.py`. |
| `gitlab-ci-local` exits 137 immediately on macOS | Unsigned ubi binary was killed by Gatekeeper. `mise.toml` pins the `npm:gitlab-ci-local` backend instead; `mise install` picks it up. |
| `gitlab-ci-local --cwd` complains about absolute paths | Pass a relative path: `python3 -c "import os;print(os.path.relpath('$tmp'))"`. |
| `gitlab-ci-local --list-json \| jq` fails | stderr noise about git fallback mixed into stdout; redirect separately: `gcl --list-json > out.log 2> err.log`. |
| Jenkins job was UI-edited but the change disappears on restart | Expected: `init.groovy.d/50-seed-pipelines.groovy` reapplies `pipelines/*.Jenkinsfile` on every boot. Edit the source file instead. |
| `just reload-casc` fails with `No such command reload-configuration-as-code` | Recent JCasC plugin renamed the verb to `apply-configuration`. The recipe in this repo already uses the new name. |

---

## Extending

### Add a new `just` group

1. Create `just.d/<group>.just`.
2. Add `import './just.d/<group>.just'` to the root `justfile`.
3. Variables from the root `justfile` (`{{cli}}`, `{{jenkins_url}}`, …) are
   automatically visible in the new file.

### Add a build agent

1. Add a second service in `docker-compose.yml` using
   `jenkins/inbound-agent`, connecting back to the controller on port
   `50000`.
2. Register the agent node in `jcasc/jenkins.yaml`:
   ```yaml
   jenkins:
     nodes:
       - permanent:
           name: "linux-agent-1"
           remoteFS: "/home/jenkins"
           launcher:
             inbound:
               workDirSettings:
                 disabled: false
   ```
3. `just reload-casc` → the agent appears under *Manage Nodes*.

### Add a new Jenkinsfile example

1. Drop `pipelines/<name>.Jenkinsfile` — seed hook picks it up.
2. (Optional) Add `test/fixtures/<name>.variables.yml` if the converted
   YAML will need CI/CD variables for local validation.
3. Regenerate the GitLab sample:
   ```bash
   just pipeline-export <name>
   just j2gitlab <name> > example/j2gitlab/samples/<name>.gitlab-ci.yml
   just test-gitlab
   ```

### Hot-reload init.groovy.d during development

`init.groovy.d/` is bind-mounted read-only. Edit the hook, then either:
- `just restart` (runs the hooks in order), or
- trigger a targeted reload from the Groovy console:
  ```bash
  just cli groovy = <<< 'load("/var/jenkins_home/init.groovy.d/50-seed-pipelines.groovy")'
  ```

### Manage secrets without committing them

Override via `.mise.local.toml` (git-ignored):

```toml
[env]
JENKINS_ADMIN_PASSWORD = "my-real-lab-password"
DEMO_API_TOKEN         = "actual-bearer-token"
```

`mise` merges local over global automatically. `just restart` re-applies
JCasC with the overridden values.

### Wire into CI

```yaml
# example GitHub Actions step
- uses: jdx/mise-action@v2
- run: |
    just up
    just wait-ready
    just test-gitlab
```

`just test-gitlab` exits 0 on success, 1 on first failure — safe to use as
a pipeline gate.
