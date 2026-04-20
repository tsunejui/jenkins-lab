# test/ — testcase runner for `gitlab-ci-local`

Declare every `.gitlab-ci.yml` that should be validated in
[`testcases.yaml`](testcases.yaml), then run them through
`gitlab-ci-local` via `just test-gitlab` — no GitLab server required.

---

## Layout

```
test/
├── README.md
├── testcases.yaml                     ← declarative case list
├── run.sh                             ← runner (invoked by `just test-gitlab`)
└── fixtures/
    ├── secret-demo.variables.yml      ← placeholder vars for secret-demo
    └── gitlab-pipeline.variables.yml  ← placeholder vars for gitlab-pipeline
```

---

## `testcases.yaml` format

```yaml
cases:
  <name>:                              # referenced from `just test-gitlab <name>`
    description: "short human-readable blurb (shown in the picker)"
    pipeline: path/to/.gitlab-ci.yml   # relative to the repo root
    variables: path/to/vars.yml        # optional, copied as
                                       # .gitlab-ci-local-variables.yml
```

Bundled cases:

| Name | Pipeline | Notes |
|---|---|---|
| `hello-world` | `example/j2gitlab/samples/hello-world.gitlab-ci.yml` | Converter output — echo / sh / sh block |
| `secret-demo` | `example/j2gitlab/samples/secret-demo.gitlab-ci.yml` | Converter output — `withCredentials` flattened |
| `gitlab-pipeline` | `example/gitlab-pipeline/.gitlab-ci.yml` | Hand-written reference — 9 jobs, 5 images |

Add a new case by appending another entry under `cases:` — the runner
picks it up on next invocation.

---

## Run

```bash
just test-gitlab                       # interactive gum picker
just test-gitlab hello-world           # parse + execute a specific case
just test-gitlab all                   # parse every case (lint-only, fast)
./test/run.sh <name>                   # direct, bypasses just
```

### What each mode does

| Argument | Parse (list) | Execute |
|---|---|---|
| (picker → `all`) | ✅ every case | ❌ |
| (picker → specific) | ✅ that case | ✅ that case |
| `all` | ✅ every case | ❌ |
| `<name>` | ✅ that case | ✅ that case |

Full execution needs Docker running — images for the picked pipeline get
pulled and each job runs inside its own container. `all` is schema /
syntax only and completes in seconds.

---

## Example output

```
$ just test-gitlab all
=== hello-world        parse + list ===
    + gitlab-ci-local --cwd …/tmp.abc --list-json
    OK — 3 job(s) detected
=== secret-demo        parse + list ===
    + gitlab-ci-local --cwd …/tmp.def --list-json
    OK — 3 job(s) detected
=== gitlab-pipeline    parse + list ===
    + gitlab-ci-local --cwd …/tmp.ghi --list-json
    OK — 9 job(s) detected

Parsing: 3/3 cases passed

All checks passed.
```

```
$ just test-gitlab hello-world

=== hello-world        2026-04-20T22:15:34+08:00 ===
  pipeline  : example/j2gitlab/samples/hello-world.gitlab-ci.yml

--- parse + list ---
    + gitlab-ci-local --cwd …/tmp.jkl --list-json
    OK — 3 job(s) detected

--- execute ---
    + gitlab-ci-local --cwd …/tmp.jkl
     PASS  Hello
     PASS  System info
     PASS  Done
    pipeline finished in 159 ms
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Picker doesn't appear | Running without a TTY (CI, nested pipes). Pass the case name as an argument. |
| `testcase '<name>' not found` | Name typo — run `just test-gitlab` and pick from the menu, or `yq '.cases \| keys' test/testcases.yaml`. |
| `pipeline missing: …` | Path in `testcases.yaml` is wrong or the file got renamed. Paths are relative to repo root. |
| `Cannot connect to the Docker daemon` | Execute mode needs Docker running. Use `all` for parse-only. |

---

## Related docs

- [`docs/test-gitlab-cicd.md`](../docs/test-gitlab-cicd.md) — full Jenkins → GitLab CI flow
- [`example/j2gitlab/README.md`](../example/j2gitlab/README.md) — converter internals
- [`example/gitlab-pipeline/README.md`](../example/gitlab-pipeline/README.md) — hand-written reference
