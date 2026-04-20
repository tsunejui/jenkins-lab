// Second demo pipeline — confirms multi-file seeding from ./pipelines/.
pipeline {
    agent any
    stages {
        stage('Disk') {
            steps {
                sh 'df -h /'
            }
        }
        stage('Memory') {
            steps {
                sh 'free -h 2>/dev/null || vm_stat | head'
            }
        }
    }
}
