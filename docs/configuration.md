# Configuration: JCasC, credentials, env, re-init

---

## Environment variable flow

All configuration flows through a single chain. Change the value once, the
right commands pick it up automatically.

```
mise.toml [env]                 ← edit here; commit `.mise.local.toml` overrides are gitignored
     │
     ▼  (shell/activation)
export JENKINS_URL / JENKINS_ADMIN_ID / JENKINS_ADMIN_PASSWORD / DEMO_*
     │
     ├───▶ docker-compose.yml   — propagates to container env
     │        │
     │        ▼
     │    CASC_JENKINS_CONFIG → /var/jenkins_jcasc/jenkins.yaml
     │        │
     │        ▼
     │    jcasc/jenkins.yaml    — substitutes ${VAR} on Jenkins boot
     │                             (admin account, credentials, location)
     │
     └───▶ justfile + scripts/  — `env_var_or_default` for CLI auth
```

---

## Editing JCasC

1. Edit `jcasc/jenkins.yaml`.
2. Apply:
   - `just reload-casc` — hot apply via `apply-configuration`, no restart.
   - `just restart` — full container restart if the change touches env vars
     that need re-reading.
3. On bad YAML the container raises `BootFailure`; check `just logs` for the
   exact exception (usually `UnknownAttributesException`).

### Common JCasC edits

**Add a user:**
```yaml
jenkins:
  securityRealm:
    local:
      users:
        - id: "${JENKINS_ADMIN_ID}"
          password: "${JENKINS_ADMIN_PASSWORD}"
        - id: "rex"
          password: "${REX_PASSWORD}"
```
Then add `REX_PASSWORD` to `mise.toml` `[env]`, pass it in
`docker-compose.yml`, and `just restart`.

**Switch authorization strategy:**
```yaml
jenkins:
  authorizationStrategy:
    globalMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"
        - "Job/Build:authenticated"
```

**Install a new plugin:**
1. Add to `plugins.txt` (one name per line).
2. `just upgrade` — rebuilds the image and recreates the container.

---

## Credentials

Credentials are declared in `jcasc/jenkins.yaml` under `credentials:` and
recreated on every apply. Jenkins encrypts them inside `data/jenkins_home`
at rest — the yaml only holds references to env-provided secrets.

```yaml
credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "demo-api-token"
              secret: "${DEMO_API_TOKEN:-lab-api-token-change-me}"
              description: "…"
          - usernamePassword:
              scope: GLOBAL
              id: "demo-basic-auth"
              username: "${DEMO_USER_ID:-demo}"
              password: "${DEMO_USER_PASSWORD:-demo-password}"
```

### Demo credentials shipped with the lab

| ID | Type | Source env (default) |
|---|---|---|
| `demo-api-token` | Secret text | `DEMO_API_TOKEN` (`lab-api-token-change-me`) |
| `demo-basic-auth` | Username + password | `DEMO_USER_ID` / `DEMO_USER_PASSWORD` (`demo` / `demo-password`) |

### Using a credential from a Jenkinsfile

```groovy
withCredentials([string(credentialsId: 'demo-api-token', variable: 'API_TOKEN')]) {
    sh 'curl -H "Authorization: Bearer $API_TOKEN" https://example.com/api'
}
```

Jenkins masks `$API_TOKEN` as `****` in the console — see
[`pipelines.md`](pipelines.md#using-secrets) for the full demo, and
`pipelines/secret-demo.Jenkinsfile` for runnable reference code.

---

## Changing the admin password

```bash
# 1. Edit JENKINS_ADMIN_PASSWORD in mise.toml (or .mise.local.toml)
just restart && just reload-casc       # keep existing data, rotate the bcrypt hash
```

Or start from scratch:
```bash
just reinit                            # wipes data + rebuilds; confirms first
```

---

## Re-initialising

Pick the right level based on what changed:

| Change | Command | Rationale |
|---|---|---|
| `pipelines/*.Jenkinsfile`, `jcasc/jenkins.yaml`, `init.groovy.d/*.groovy` | `just restart` | Bind-mounted; the container re-reads the files on boot. For JCasC alone, `just reload-casc` hot-reloads without restart. |
| `plugins.txt`, `Dockerfile` | `just upgrade` | Rebuilds the image (pulls base) and recreates the container; local `data/` is preserved. |
| Clean slate (forgot password, corrupted state, bcrypt mismatch) | `just reinit` | Destroys container + wipes `./data/jenkins_home` + rebuilds + starts fresh. Confirms first. |

`init.groovy.d/` is bind-mounted at runtime (not baked into the image), so
editing a hook + `just restart` is always enough.

---

## Local-only overrides

Put sensitive / machine-specific values in `.mise.local.toml` (already in
`.gitignore`) rather than `mise.toml`:

```toml
# .mise.local.toml
[env]
JENKINS_ADMIN_PASSWORD = "my-real-lab-password"
DEMO_API_TOKEN         = "actual-bearer-from-vault"
```

`mise` auto-merges local over global, so a `just restart` after editing
picks up the new values.
