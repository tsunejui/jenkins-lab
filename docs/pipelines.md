# Pipelines: creation, inspection, secrets

---

## Three ways to define a pipeline

| Approach | Source location | Applied by | When it re-applies | Use when… |
|---|---|---|---|---|
| **A. Jenkinsfile + seed hook** | `pipelines/<name>.Jenkinsfile` | `init.groovy.d/50-seed-pipelines.groovy` on container boot | Every `just up` / `just restart` | Pure Declarative Pipelines (the common case); you want Groovy syntax highlighting and minimal boilerplate. |
| **B. Full XML via Jenkins CLI** | `jobs/<name>.xml` | `just job-apply <name>` | On demand | Non-Pipeline job types, or Pipelines that need custom triggers / parameters / properties the script block can't express. |
| **C. JCasC `jobs:` block** | `jcasc/jenkins.yaml` (inline Job DSL) | JCasC apply/reload | `just reload-casc` or restart | Keeping a small, static set of seed jobs next to the rest of JCasC config. |

All three routes coexist — they target the same `WorkflowJob` object in
Jenkins, with whichever ran last winning. Keep one source of truth per job.

---

## A. Jenkinsfile approach (recommended)

```bash
cat > pipelines/my-pipeline.Jenkinsfile <<'EOF'
pipeline {
    agent any
    stages {
        stage('Hello') { steps { echo 'hi' } }
    }
}
EOF

just restart                 # init.groovy.d picks up the new file
just job-build my-pipeline   # ready to run
```

How the hook works — `init.groovy.d/50-seed-pipelines.groovy`:

```groovy
dir.eachFileMatch(~/.*\.Jenkinsfile$/) { file ->
    def name = file.name - ~/\.Jenkinsfile$/
    def job  = Jenkins.instance.getItemByFullName(name, WorkflowJob)
        ?: Jenkins.instance.createProject(WorkflowJob, name)
    job.definition = new CpsFlowDefinition(file.text, true)  // sandbox=true
    job.save()
}
```

Pros:
- Pipeline code stays a first-class `.groovy` file (IDE/LSP support).
- Adding / editing a pipeline is one file operation + `just restart`.
- UI edits are **ephemeral** — the hook overwrites them on next boot
  (GitOps-style reconciliation).

---

## B. Full XML approach

```bash
# Dump an existing job you want to tweak
just job-dump hello-world          # → jobs/hello-world.xml

cp jobs/hello-world.xml jobs/my-pipeline.xml
vim jobs/my-pipeline.xml           # edit triggers / parameters / etc.

just job-apply my-pipeline         # create-or-update via Jenkins CLI
just job-build my-pipeline
```

Interactive equivalent: `just pipeline` → `apply` → pick file → `build`.

---

## C. JCasC `jobs:` approach

```yaml
# jcasc/jenkins.yaml
jobs:
  - script: |
      pipelineJob('jcasc-demo') {
        description('Defined inline in JCasC via Job DSL')
        definition {
          cps {
            sandbox(true)
            script('''
              pipeline {
                  agent any
                  stages {
                      stage('Hello') { steps { echo 'from JCasC' } }
                  }
              }
            '''.stripIndent())
          }
        }
      }
```

Apply with `just reload-casc` (no container restart required). Good for
short, static definitions that benefit from living next to the rest of the
JCasC config.

---

## Inspecting pipelines

| Goal | Command | Data source |
|---|---|---|
| All pipelines + status | `just pipelines` | REST `/api/json` |
| Static definition (script, stage labels) | `just pipeline-info <name>` | CLI `get-job` (config.xml) |
| Runtime state of last build | `just pipeline-status <name>` | REST + wfapi |
| Runtime state of a specific build | `just pipeline-status <name> 3` | REST |
| Raw config.xml | `just cli get-job <name>` | CLI |
| Complete artefact dump | `just pipeline-export <name>` | CLI + REST |

Why split `pipeline-info` (CLI) from `pipeline-status` (REST):
- **CLI** is the authoritative source of the job's *definition* — what it's
  supposed to do.
- **REST** is how you observe *execution* — result, timing, stages,
  history. There's no CLI command that returns structured build data.

---

## <a id="using-secrets"></a>Using secrets

Credentials are provisioned by JCasC (see
[`configuration.md`](configuration.md#credentials)). A Jenkinsfile binds
them with `withCredentials`:

```groovy
pipeline {
    agent any
    stages {
        stage('String secret') {
            steps {
                withCredentials([string(credentialsId: 'demo-api-token',
                                        variable: 'API_TOKEN')]) {
                    sh '''
                        echo "Token length: ${#API_TOKEN}"
                        echo "Raw value: $API_TOKEN"     # printed as ****
                        curl -H "Authorization: Bearer $API_TOKEN" https://example.com/api
                    '''
                }
            }
        }
        stage('Username + password') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'demo-basic-auth',
                                                   usernameVariable: 'DEMO_USER',
                                                   passwordVariable: 'DEMO_PASS')]) {
                    sh 'echo "$DEMO_USER / ****"'
                }
            }
        }
    }
}
```

Jenkins masks any bound variable as `****` wherever it appears in the
console — even when the pipeline deliberately tries to print it, or when
an HTTP response echoes the value back. **That safety only applies inside
the `withCredentials` scope and for the variable names you bound**; copying
the value into another variable bypasses the masker.

Run the reference pipeline to see this in action:

```bash
just job-build secret-demo
```

Output includes lines like:
```
+ echo 'API_TOKEN length : 23'
API_TOKEN length : 23
+ echo 'Raw value in log : ****'
Raw value in log : ****
```

---

## Converting to GitLab CI/CD

Once a pipeline is proven on Jenkins, you can generate an approximate
`.gitlab-ci.yml` for migration:

```bash
just pipeline-export my-pipeline          # dumps config.xml to exports/
just j2gitlab       my-pipeline > .gitlab-ci.yml   # converts, print to stdout
just test-gitlab                          # validate + run via gitlab-ci-local
```

Full end-to-end walkthrough with the flow diagram:
[`docs/test-gitlab-cicd.md`](test-gitlab-cicd.md). Converter internals and
limitations: [`example/j2gitlab/README.md`](../example/j2gitlab/README.md).
