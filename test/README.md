# test/ — validate generated GitLab CI YAML

Exercises every `example/j2gitlab/samples/*.gitlab-ci.yml` with
[`gitlab-ci-local`](https://github.com/firecow/gitlab-ci-local) to prove the
converter output is consumable by a real GitLab runner — without needing to
push anything to GitLab.

---

## Run

```bash
just test-gitlab        # recommended
./test/run.sh           # direct
```

`gitlab-ci-local` is pinned via `mise.toml` (`npm:gitlab-ci-local`), so a
fresh clone only needs `mise install`.

---

## What it checks

| Step | Scope | Why |
|---|---|---|
| `gitlab-ci-local --list-json` | every sample | YAML syntax + schema validation; detects job count |
| `gitlab-ci-local` (full run) | `hello-world` only | end-to-end proof using pure shell steps (no credentials, no network) |

Additional fixtures live under `test/fixtures/`. When a sample has a
matching `<name>.variables.yml`, that file is copied alongside the pipeline
as `.gitlab-ci-local-variables.yml` so bound variables resolve without real
secrets.

---

## Layout

```
test/
├── README.md
├── run.sh                             # runner (see `just test-gitlab`)
└── fixtures/
    └── secret-demo.variables.yml      # placeholder credentials for secret-demo
```

---

## Expected output

```
=== hello-world      parse + list ===
    OK — 3 job(s) detected
=== secret-demo      parse + list ===
    OK — 3 job(s) detected

Parsing: 2/2 pipelines passed.

=== hello-world               execute   ===
    parsing and downloads finished in 32 ms.
    Hello       finished in 7.75 ms
    System info finished in 11 ms
    Done        finished in 7.94 ms
     PASS  Hello      
     PASS  System info
     PASS  Done       
    pipeline finished in 157 ms
    end-to-end OK

All checks passed.
```

Script exits 0 on success so it's safe to wire into CI later.

---

## Extending

- To run `secret-demo` end-to-end too, add another block after the hello-world
  execute section and depend on the variables-file copy already handled
  inside the loop.
- To test a new sample, drop the YAML into `example/j2gitlab/samples/` — the
  loop picks it up automatically; add a `test/fixtures/<name>.variables.yml`
  if the pipeline expects CI variables.
- To dig into a specific sample interactively:
  ```bash
  tmp=$(mktemp -d); cp example/j2gitlab/samples/secret-demo.gitlab-ci.yml "$tmp/.gitlab-ci.yml"
  cp test/fixtures/secret-demo.variables.yml "$tmp/.gitlab-ci-local-variables.yml"
  mise exec npm:gitlab-ci-local -- gitlab-ci-local --cwd "$(realpath --relative-to=. "$tmp")" --preview
  ```
