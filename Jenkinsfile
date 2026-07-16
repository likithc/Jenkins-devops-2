pipeline {
    agent any
    
    environment {
        APP_NAME = 'task-tracker'
        IMAGE_TAG = "${BUILD_NUMBER}"
        
        // Docker Hub Setup
        DOCKER_REGISTRY = 'https://index.docker.io/v1/' 
        APP_IMAGE = "dockerhub/${APP_NAME}" 
        DOCKER_CREDS_ID = 'dockerhub' 
        
        SLACK_CHANNEL = '#devops-alerts'
        LAST_SUCCESS_FILE = "/tmp/${APP_NAME}_last_success.txt"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Install Dependencies and Run Tests') {
            steps {
                sh 'npm install'
                sh 'npm test'
            }
        }
        
        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.withRegistry("${env.DOCKER_REGISTRY}", "${env.DOCKER_CREDS_ID}") {
                        def customImage = docker.build("${env.APP_IMAGE}:${env.IMAGE_TAG}", "--build-arg BUILDKIT_INLINE_CACHE=1 .")
                        customImage.push()
                        
                        try {
                            customImage.push("latest")
                        } catch (Exception e) {
                            echo "Warning: Failed to push latest tag, continuing..."
                        }
                    }
                }
            }
        }
        
        stage('Deploy') {
            steps {
                script {
                    docker.withRegistry("${env.DOCKER_REGISTRY}", "${env.DOCKER_CREDS_ID}") {
                        sh """
                            export APP_IMAGE="${env.APP_IMAGE}"
                            export IMAGE_TAG="${env.IMAGE_TAG}"
                            docker-compose down --remove-orphans
                            docker-compose up -d
                        """
                    }
                }
            }
        }
        
        stage('Curl Verify') {
            steps {
                script {
                    echo "Waiting for application readiness..."
                    sh '''
                        timeout 60 bash -c '
                        while [[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)" != "200" ]]; do
                            echo "Waiting for application app to respond on port 3000..."
                            sleep 2
                        done'
                    '''
                    
                    echo "Application is verified online. Fetching endpoint readouts:"
                    sh 'curl -s http://localhost:3000/'
                    sh 'curl -s http://localhost:3000/health'
                    sh 'curl -s http://localhost:3000/api/tasks'
                }
            }
        }
    }
    
    post {
        success {
            script {
                sh "echo ${env.IMAGE_TAG} > ${env.LAST_SUCCESS_FILE}"
                try {
                    slackSend(channel: "${env.SLACK_CHANNEL}", color: 'good', message: "✅ SUCCESS: Build #${env.BUILD_NUMBER} of ${env.APP_NAME} deployed successfully.\nView: ${env.BUILD_URL}")
                } catch (Exception e) {
                    echo "Slack notification skipped: Setup credentials in Jenkins to enable alerts."
                }
            }
        }
        failure {
            script {
                echo "Deployment failed. Evaluated stable context initialization..."
                
                def fileExists = sh(script: "[ -f ${env.LAST_SUCCESS_FILE} ] && echo 'true' || echo 'false'", returnStdout: true).trim()
                def rollbackTag = "latest"
                
                if (fileExists == 'true') {
                    rollbackTag = sh(script: "cat ${env.LAST_SUCCESS_FILE}", returnStdout: true).trim()
                }
                
                echo "Initiating rollback deployment sequence to tag target: ${rollbackTag}"
                
                try {
                    docker.withRegistry("${env.DOCKER_REGISTRY}", "${env.DOCKER_CREDS_ID}") {
                        sh """
                            export APP_IMAGE="${env.APP_IMAGE}"
                            export IMAGE_TAG="${rollbackTag}"
                            docker-compose down
                            docker-compose up -d
                        """
                    }
                } catch (Exception e) {
                    echo "Rollback execution halted: No valid historical images are available to pull yet."
                }

                try {
                    slackSend(channel: "${env.SLACK_CHANNEL}", color: 'danger', message: "🚨 FAILURE: Build #${env.BUILD_NUMBER} of ${env.APP_NAME} failed.\nView: ${env.BUILD_URL}")
                } catch (Exception e) {
                    echo "Slack notification skipped: Setup credentials in Jenkins to enable alerts."
                }
            }
        }
        always {
            sh 'docker image prune -f --filter "until=24h"'
        }
        cleanup {
            cleanWs()
        }
    }
}
