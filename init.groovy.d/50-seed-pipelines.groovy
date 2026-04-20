// Auto-seed pipeline jobs from Jenkinsfiles mounted at /var/jenkins_pipelines.
// Runs on every Jenkins boot; creates missing jobs and updates existing ones
// so the Jenkinsfile in the repo is the single source of truth.
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def dir = new File('/var/jenkins_pipelines')
if (!dir.exists()) {
    println '[seed-pipelines] /var/jenkins_pipelines not mounted — skipping'
    return
}

def jenkins = Jenkins.instance
dir.eachFileMatch(~/.*\.Jenkinsfile$/) { file ->
    def name = file.name.replaceAll(/\.Jenkinsfile$/, '')
    def script = file.text

    def job = jenkins.getItemByFullName(name, WorkflowJob)
    def action
    if (job == null) {
        job = jenkins.createProject(WorkflowJob, name)
        action = 'created'
    } else {
        action = 'updated'
    }
    job.definition = new CpsFlowDefinition(script, true) // sandbox = true
    job.save()
    println "[seed-pipelines] ${action} ${name} ← ${file.name}"
}
