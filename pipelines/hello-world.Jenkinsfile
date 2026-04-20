// Canonical pipeline definition for the hello-world job.
// Loaded by init.groovy.d/50-seed-pipelines.groovy on every Jenkins boot,
// which creates or updates the `hello-world` WorkflowJob with this script.
pipeline {
    agent any
    stages {
        stage('Hello') {
            steps {
                echo 'Hello, World from Jenkins!'
            }
        }
        stage('System info') {
            steps {
                sh '''
                    echo "Node : $(uname -a)"
                    echo "User : $(whoami)"
                    echo "Date : $(date -Iseconds)"
                '''
            }
        }
        stage('Done') {
            steps {
                echo "Build #${env.BUILD_NUMBER} finished on ${env.NODE_NAME}"
            }
        }
    }
}
