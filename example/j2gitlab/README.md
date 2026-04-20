# j2gitlab — Jenkins Pipeline → GitLab CI/CD YAML

A small tool that reads a Jenkins pipeline's `config.xml` (exported by
`just pipeline-export`) and emits an approximate `.gitlab-ci.yml` on stdout.

This is a **lab-grade converter**: it handles the ~80% of Declarative
Pipelines that map cleanly onto GitLab's model. The remaining 20% (shared
libraries, agents, matrix builds, post-actions, environment blocks,
conditional `when { }`) need manual review.

---

## Usage

```bash
# Prerequisite: dump the pipeline into ./exports/
just pipeline-export hello-world

# Convert — output goes to stdout
just j2gitlab hello-world

# …or pipe / redirect it
just j2gitlab hello-world > .gitlab-ci.yml

# Different export root
./example/j2gitlab/j2gitlab.py my-pipeline /tmp/exports
```

Inputs the tool looks for:

```
<EXPORTS_DIR>/<NAME>/config.xml    ← the only file actually read
```

---

## What gets converted

| Jenkins (Declarative) | GitLab CI/CD |
|---|---|
| `pipeline { stages { stage('X') { steps { … } } } }` | `stages: [X]` + a job per stage |
| `echo 'msg'` | `script: [echo 'msg']` |
| `sh 'cmd'` | `script: [cmd]` |
| `sh '''multi\nline\nscript'''` | `script: [ \| \n multi\n line\n ]` (block scalar) |
| `withCredentials([string(credentialsId: 'x', variable: 'V')]) { … }` | top-level `variables: { V: "${V}" }` + flattened inner steps |
| `withCredentials([usernamePassword(…)]) { … }` | two variables (username + password) + flattened inner |

What's **not** translated (falls through to a comment or is silently ignored):

- `agent { … }` (GitLab has `image:` / tags; you'll add manually)
- `options { … }`, `triggers { … }`, `parameters { … }`
- `when { … }` — GitLab uses `rules:` / `only:`; conversion needs intent
- `post { always { … } }` — GitLab's `after_script:` is per-job
- `parallel { }` — GitLab's `parallel: matrix:` is structurally different
- Shared libraries (`@Library`)
- Non-Declarative / Scripted Pipelines

The tool adds a header comment reminding you to review before commit.

---

## Conversion examples

Generated from the repo's demo pipelines — refresh via:

```bash
just pipeline-export hello-world  && just j2gitlab hello-world  > example/j2gitlab/samples/hello-world.gitlab-ci.yml
just pipeline-export secret-demo  && just j2gitlab secret-demo  > example/j2gitlab/samples/secret-demo.gitlab-ci.yml
```

- [`samples/hello-world.gitlab-ci.yml`](samples/hello-world.gitlab-ci.yml) — plain echo / sh / multi-line sh
- [`samples/secret-demo.gitlab-ci.yml`](samples/secret-demo.gitlab-ci.yml) — `withCredentials` flattened into `variables:`

---

## Design notes

- **Language choice**: Python (stdlib only). Parsing Groovy with balanced
  brace / quote awareness is easier in Python than in bash+awk. The main
  `scripts/` directory stays pure bash; this tool is intentionally isolated.
- **No YAML library**: the emitter hand-writes YAML to keep the dependency
  footprint zero. If the output ever needs richer structures,
  `pyyaml` + `safe_dump` would be the natural upgrade.
- **Why read `config.xml`, not `Jenkinsfile`**: the tool works against any
  Jenkins controller you can reach — you don't need the original source,
  just `just pipeline-export`. The pipeline script is extracted from
  `<script>…</script>` inside the XML and entity-decoded.

---

## Limitations worth knowing

1. **Credentials are flattened, not enforced.** In Jenkins, values bound
   by `withCredentials` are masked in logs. GitLab also masks project
   CI/CD variables, but only if the variable is marked as *masked*. The
   generated YAML expects the project admin to configure that.
2. **`${env.X}` references are left verbatim.** Jenkins-specific env
   (`BUILD_NUMBER`, `NODE_NAME`) don't exist in GitLab; you'll want to
   replace them with predefined GitLab variables (`CI_JOB_ID`,
   `CI_RUNNER_DESCRIPTION`, etc.) by hand.
3. **Dedent is heuristic.** Multi-line `sh '''…'''` blocks are dedented
   via `textwrap.dedent`, which works when all lines share a common
   indent — as they do in the canonical Jenkinsfile style.
