// Demonstrates how to consume Jenkins credentials from a Declarative Pipeline.
//
// Both credentials are provisioned by jcasc/jenkins.yaml on controller boot:
//   - demo-api-token   (string, id: demo-api-token)
//   - demo-basic-auth  (username/password, id: demo-basic-auth)
//
// Jenkins automatically masks secret values as "****" in the console log.
pipeline {
    agent any
    stages {
        stage('String secret') {
            steps {
                withCredentials([string(credentialsId: 'demo-api-token',
                                        variable: 'API_TOKEN')]) {
                    sh '''
                        echo "API_TOKEN length : ${#API_TOKEN}"
                        echo "Raw value in log : $API_TOKEN"   # printed as ****
                        curl -sS --max-time 3 \
                             -H "Authorization: Bearer $API_TOKEN" \
                             https://httpbin.org/bearer || true
                    '''
                }
            }
        }

        stage('Username + password') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'demo-basic-auth',
                                                   usernameVariable: 'DEMO_USER',
                                                   passwordVariable: 'DEMO_PASS')]) {
                    sh '''
                        echo "Username        : $DEMO_USER"
                        echo "Password length : ${#DEMO_PASS}"
                        echo "Raw value in log: $DEMO_PASS"    # printed as ****
                    '''
                }
            }
        }

        stage('Leak test') {
            steps {
                // Even if we deliberately try to echo the value, the console
                // masker replaces it — never trust that as a safety net,
                // though: it only works for bound variables in this stage.
                withCredentials([string(credentialsId: 'demo-api-token',
                                        variable: 'TOKEN')]) {
                    sh 'printf "leak attempt: %s\\n" "$TOKEN"'
                }
            }
        }
    }
}
