# Multi-image GitLab CI demo

A hand-written `.gitlab-ci.yml` that mixes several container images to
illustrate the patterns most pipelines end up using. Meant as a live
reference you can run locally — and as a reality-check for
[`example/j2gitlab/samples/`](../j2gitlab/samples/), the converter's
auto-generated output.

---

## What this pipeline shows

```
preflight        test              build          publish           deploy
─────────        ────              ─────          ───────           ──────
preflight:yaml   test:python       build:binary   publish:inspect   deploy:api-auth
preflight:env    test:node                        (needs build)     deploy:registry-login
                                                                    deploy:kubeconfig
                                                                    (all need publish)
```

| Concept | Where |
|---|---|
| `default:` image as a fallback | top of the yaml (`alpine:3.20`) |
| Per-job image override | every `image:` in every job |
| Parallel jobs in one stage | `test:python` + `test:node`; three `deploy:*` jobs |
| Artifact passing | `build:binary` saves `demo-app`, `publish:inspect` consumes it |
| DAG scheduling | `publish:inspect.needs: [build:binary]`; `deploy:* needs: publish:inspect` |
| Variables | top-level `APP_NAME` / `APP_VERSION` + predefined `CI_*` |
| Secrets (masked string + user/pass + string-as-file) | `deploy:*` jobs |
| Inline scripts | Python / Node / Go code via shell heredocs |

Images involved: `alpine:3.20`, `cytopia/yamllint:latest`,
`python:3.12-alpine`, `node:20-alpine`, `golang:1.22-alpine`.

---

## Prerequisites

- A running Docker daemon (Docker Desktop / Rancher Desktop / OrbStack
  — whatever you use for the Jenkins lab)
- `mise install` at the repo root — pins `gitlab-ci-local@4.71.0`

You do **not** need a GitLab server, a runner registration, or the
Jenkins container. `gitlab-ci-local` runs every job as a one-shot
docker container on your host.

---

## Quick test

```bash
# From the repo root
mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd example/gitlab-pipeline --list
```

Expected output:
```
name             description  stage      when        allow_failure  needs
preflight:yaml                preflight  on_success  false
preflight:env                 preflight  on_success  false
test:python                   test       on_success  false
test:node                     test       on_success  false
build:binary                  build      on_success  false
publish:inspect               publish    on_success  false          [build:binary]
```

Run everything end-to-end:
```bash
mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd example/gitlab-pipeline
```

First run pulls all five images (~400 MB compressed); subsequent runs
reuse the cache and finish in seconds.

---

## Running a single job

Useful while iterating on one image / script:

```bash
mise exec npm:gitlab-ci-local -- gitlab-ci-local \
    --cwd example/gitlab-pipeline \
    "test:python"
```

Any job name from the `--list` table works. Colons are fine as long as
the name is quoted.

---

## Inspect what GitLab would see

`--preview` expands `default:`, `extends:`, `include:` etc. — show exactly
what a real GitLab runner would receive:

```bash
mise exec npm:gitlab-ci-local -- gitlab-ci-local \
    --cwd example/gitlab-pipeline --preview
```

---

## Convenience: shell aliases

If you use the demo repeatedly, the easiest ergonomic fix is a shell
alias:

```bash
alias gcl='mise exec npm:gitlab-ci-local -- gitlab-ci-local'
cd example/gitlab-pipeline
gcl --list
gcl test:python
gcl          # full run
```

---

## Secrets / CI/CD variables

The `deploy:*` jobs expect three kinds of variables that a real GitLab
project would configure under *Settings → CI/CD → Variables* (with
**Masked** + **Protected** enabled for anything sensitive):

| Variable | Kind | Consumed by |
|---|---|---|
| `DEPLOY_API_TOKEN` | Masked string | `deploy:api-auth` |
| `REGISTRY_USER` / `REGISTRY_PASSWORD` | String + masked string | `deploy:registry-login` |
| `KUBECONFIG_CONTENT` | Multi-line string (written to `/tmp/kubeconfig` at runtime) | `deploy:kubeconfig` |

### Providing them locally

A ready-to-use fixture lives at
[`test/fixtures/gitlab-pipeline.variables.yml`](../../test/fixtures/gitlab-pipeline.variables.yml)
with placeholder values. Copy it into the pipeline's working directory
as `.gitlab-ci-local-variables.yml` (the filename `gitlab-ci-local`
auto-discovers):

```bash
cp test/fixtures/gitlab-pipeline.variables.yml \
   example/gitlab-pipeline/.gitlab-ci-local-variables.yml

mise exec npm:gitlab-ci-local -- gitlab-ci-local \
    --cwd example/gitlab-pipeline \
    'deploy:api-auth' 'deploy:registry-login' 'deploy:kubeconfig'
```

`.gitlab-ci-local-variables.yml` is git-ignored via the repo-wide
`.gitlab-ci-local/` rule for its sibling cache; the fixture itself
(`test/fixtures/gitlab-pipeline.variables.yml`) is tracked so anyone
can reproduce the demo.

### Using real secrets

Never commit the fixture's values to anything that matters. For a real
deployment:

1. Add each variable in GitLab (*Settings → CI/CD → Variables*).
2. Mark tokens / passwords / kubeconfig content as **Masked** so GitLab
   redacts them in logs, and **Protected** so only protected branches /
   tags can read them.
3. GitLab masking is **per-variable and per-exact-string** — copying a
   value into another variable or into generated output re-exposes it.
   Keep the bound env-var usage tight like the demo shows.

For a deep-dive on the same topic from the Jenkins side, see
[`docs/pipelines.md#using-secrets`](../../docs/pipelines.md#using-secrets).

---

## Variables and artifacts

The pipeline exposes `APP_NAME=demo-app` and `APP_VERSION=1.0.0` as
project-level variables — they get echoed by `preflight:env`, baked
into the Go binary by `build:binary`, and echoed again by
`publish:inspect`.

`build:binary` produces `demo-app` as an artifact. `gitlab-ci-local`
stores artifacts under `.gitlab-ci-local/artifacts/` next to the
yaml; `publish:inspect` unpacks the artifact automatically before
running because of its `needs: [build:binary]` declaration.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | Docker isn't running — start Docker Desktop / Rancher / OrbStack. |
| `Please use relative path for the --cwd option` | Pass a relative path: `--cwd example/gitlab-pipeline`. |
| First run takes several minutes | Image pulls. Subsequent runs use the local docker cache. |
| `image pull backoff` for `cytopia/yamllint` | Check Docker Hub rate limits / authenticate: `docker login`. |
| `test:python` can't find my script | This yaml is fully self-contained — scripts live in heredocs inside the yaml, not in separate files. |

---

## Relationship to the rest of the repo

| Use case | Which artefact |
|---|---|
| Reference "what a good multi-image pipeline looks like" | this file |
| Auto-converted from a Jenkins pipeline | [`example/j2gitlab/samples/`](../j2gitlab/samples/) |
| End-to-end conversion + validation harness | [`test/`](../../test/) (uses `gitlab-ci-local` the same way) |
| Explaining the conversion flow step-by-step | [`docs/test-gitlab-cicd.md`](../../docs/test-gitlab-cicd.md) |
