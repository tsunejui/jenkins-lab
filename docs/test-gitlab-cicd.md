# End-to-end: Jenkins pipeline → GitLab CI/CD validation

This walkthrough takes a pipeline from **a fresh clone of the repo** through
to **a GitLab CI YAML validated locally by `gitlab-ci-local`**. Each step
names the `just` recipe and the file it reads / writes so you can jump in
at any point.

```
                  ┌─────────────────────┐
┌───────┐  seed   │  Jenkins controller │  export
│ repo  │───────▶ │  (pipeline runs)    │────────┐
└───────┘         └─────────────────────┘        │
    │                                             ▼
    │                                      exports/<NAME>/config.xml
    │                                             │
    │                                      j2gitlab (converter)
    │                                             │
    │                                             ▼
    │                                example/j2gitlab/samples/<NAME>.gitlab-ci.yml
    │                                             │
    │                                      gitlab-ci-local (test)
    │                                             │
    └──────────────── validated YAML ◀────────────┘
```

---

## 0. Prerequisites

```bash
mise install          # just / java / gum / jq / gitlab-ci-local (versions pinned in mise.toml)
docker --version      # Docker / Rancher / OrbStack must be running
```

---

## 1. Start Jenkins and wait until it's ready

```bash
just up               # builds image (plugins + jcasc wiring), starts container
just wait-ready       # blocks until http://localhost:8090/login answers (~60s)
```

**Artefacts produced**
- Container `jenkins-lab` running on `:8090` / `:50000`
- JCasC provisions admin, credentials, and the `jcasc-demo` job
- `init.groovy.d/50-seed-pipelines.groovy` seeds every
  `pipelines/*.Jenkinsfile` as a `WorkflowJob` — so `hello-world`,
  `system-check`, `secret-demo` exist automatically

Verify:
```bash
just pipelines
# NAME          STATUS              URL
# ----------------------------------------------------------------
# hello-world   SUCCESS             http://localhost:8090/job/hello-world/
# jcasc-demo    SUCCESS             http://localhost:8090/job/jcasc-demo/
# secret-demo   SUCCESS             http://localhost:8090/job/secret-demo/
# system-check  SUCCESS             http://localhost:8090/job/system-check/
```

---

## 2. Run the Jenkins pipeline at least once

A build must exist before we can export anything meaningful.

```bash
just job-build hello-world         # trigger + stream console; expects SUCCESS
```

Check the structured outcome:
```bash
just pipeline-status hello-world   # result / duration / per-stage timing
```

---

## 3. Export the pipeline artefacts to local files

```bash
just pipeline-export hello-world   # → ./exports/hello-world/
```

Drops into `./exports/hello-world/`:

| File | Source | Used by j2gitlab? |
|---|---|---|
| `config.xml` | `cli get-job` | ✅ (main input) |
| `info.json` | REST `/api/json` | — |
| `last-build.json` | REST `/<build>/api/json` | — |
| `stages.json` | REST `/wfapi/describe` | — |
| `console.log` | REST `/consoleText` | — |

`exports/` is gitignored; rerun the export whenever the pipeline changes.

---

## 4. Convert Jenkins Pipeline → GitLab CI/CD YAML

```bash
just j2gitlab hello-world                                      # print to stdout
just j2gitlab hello-world > example/j2gitlab/samples/hello-world.gitlab-ci.yml
```

How the tool works — see [`example/j2gitlab/README.md`](../example/j2gitlab/README.md).
Short version: parses `<script>...</script>` from `config.xml` with
brace / quote awareness, maps Declarative Pipeline stages + steps
(`echo` / `sh` / `withCredentials`) into GitLab jobs, emits YAML.

Limitations (by design) — review the output before committing it to a real
project:
- `agent`, `when`, `post`, `parallel`, shared libs: not converted
- `${env.X}` left verbatim (swap to `$CI_JOB_ID`, `$CI_RUNNER_DESCRIPTION`, …)
- `withCredentials` is flattened into a top-level `variables:` block —
  the receiving GitLab project must provision these as masked CI/CD
  variables

---

## 5. Validate + run the generated YAML with `gitlab-ci-local`

No GitLab server needed — `gitlab-ci-local` is a host-side simulator.

```bash
just test-gitlab                   # scripted: lists jobs + runs hello-world e2e
```

Expected output:
```
=== hello-world      parse + list ===
    OK — 3 job(s) detected
=== secret-demo      parse + list ===
    OK — 3 job(s) detected

Parsing: 2/2 pipelines passed.

=== hello-world               execute   ===
    Hello       finished in 7 ms
    System info finished in 11 ms
    Done        finished in 7 ms
     PASS  Hello      
     PASS  System info
     PASS  Done       
    pipeline finished in 157 ms
    end-to-end OK

All checks passed.
```

Exit code 0 on success — wire into CI if desired. Full details in
[`test/README.md`](../test/README.md).

---

## 6. Manual validation for a single sample

Useful when debugging the converter or the YAML:

```bash
tmp=$(mktemp -d)
cp example/j2gitlab/samples/secret-demo.gitlab-ci.yml "$tmp/.gitlab-ci.yml"
cp test/fixtures/secret-demo.variables.yml "$tmp/.gitlab-ci-local-variables.yml"
rel=$(python3 -c "import os;print(os.path.relpath('$tmp'))")

# `mise exec npm:gitlab-ci-local -- gitlab-ci-local` (wrapped for brevity):
GCL() { mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd "$rel" "$@"; }

GCL --list                    # human-readable job table
GCL --list-json | jq .        # structured listing
GCL --preview                 # fully-expanded YAML (after includes / extends)
GCL                           # run every job
GCL "String secret"           # run a specific job
GCL --variable FOO=bar        # add one-off variable
```

---

## 7. Regenerate the samples after any tool change

Whenever you edit `example/j2gitlab/j2gitlab.py` or a Jenkinsfile:

```bash
just pipeline-export hello-world && just j2gitlab hello-world > example/j2gitlab/samples/hello-world.gitlab-ci.yml
just pipeline-export secret-demo && just j2gitlab secret-demo > example/j2gitlab/samples/secret-demo.gitlab-ci.yml
just test-gitlab              # confirm new outputs still pass validation
git diff example/j2gitlab/samples   # review what changed
```

---

## Sequence cheat-sheet

```
 ┌──────────────────────────────────────────────────────────────────┐
 │ mise install                                                     │
 │ just up                                                          │
 │ just wait-ready                                                  │
 │ just pipelines                 ← verify seeding                  │
 │ just job-build hello-world     ← at least one build must exist   │
 │ just pipeline-export hello-world                                 │
 │ just j2gitlab hello-world > example/j2gitlab/samples/…           │
 │ just test-gitlab               ← final validation                │
 └──────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `just up` hangs on first run | Image build (downloads base + plugins). ~60–90 s typical. |
| `just wait-ready` times out | Check `just logs` — usually a JCasC boot failure. |
| `just pipeline-export X` errors with `lastBuild.number // empty` | No build exists yet. Run `just job-build X` first. |
| `j2gitlab` truncates output at `#` | YAML plain scalar with `#` — already fixed (echo/sh routed through `yaml_inline`). Regenerate samples. |
| `gitlab-ci-local` exit 137 on macOS | ubi binary is unsigned; we use the `npm:` backend instead. `mise install` will pick the right one. |
| `gitlab-ci-local --cwd` rejects absolute paths | Convert via `python3 -c "import os;print(os.path.relpath('…'))"`. |
| `secret-demo` pipeline fails locally on network call | `curl https://httpbin.org/bearer` may timeout. Expected — it's a demonstration, not a contract test. |

---

## Related docs

- [`README.md`](../README.md) — project overview + full recipe reference
- [`docs/jenkins-cli.md`](./jenkins-cli.md) — how the Jenkins CLI is obtained and used
- [`example/j2gitlab/README.md`](../example/j2gitlab/README.md) — the converter's parser + limitations
- [`test/README.md`](../test/README.md) — the gitlab-ci-local harness in detail
