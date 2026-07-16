pipeline {
    agent any
    
    environment {
        APP_NAME = 'task-tracker'
        IMAGE_TAG = "${BUILD_NUMBER}"
        DOCKER_REGISTRY = 'registry.your-private-domain.com'
        DOCKER_CREDS_ID = 'dockerhub'
        GITHUB_CREDS_ID = 'github'
        SLACK_CHANNEL = '#devops-alerts'
        LAST_SUCCESS_FILE = "/tmp/${APP_NAME}_last_success.txt"
    }
    
    tools {
        nodejs 'NodeJS_20' 
    }
    
    stages {
        stage('SCM Pull') {
            steps {
                git branch: 'main', credentialsId: "${GITHUB_CREDS_ID}", url: "${GITHUB_REPO_URL}"
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
                    docker.withRegistry("https://${DOCKER_REGISTRY}", "${DOCKER_CREDS_ID}") {
                        def customImage = docker.build("${DOCKER_REGISTRY}/${APP_NAME}:${IMAGE_TAG}", "--build-arg BUILDKIT_INLINE_CACHE=1 .")
                        customImage.push()
                        customImage.push("latest") 
                    }
                }
            }
        }
        
        stage('Deploy') {
            steps {
                script {
                    docker.withRegistry("https://${DOCKER_REGISTRY}", "${DOCKER_CREDS_ID}") {
                        sh """
                            export DOCKER_REGISTRY=${DOCKER_REGISTRY}
                            export IMAGE_TAG=${IMAGE_TAG}
                            docker-compose down
                            docker-compose up -d
                        """
                    }
                }
            }
        }
        
        stage('Curl Verify') {
            steps {
                script {
                    echo "Waiting for application to become ready..."
                    sh '''
                        timeout 60 bash -c '
                        while [[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)" != "200" ]]; do
                            echo "Waiting for app to be ready..."
                            sleep 2
                        done'
                    '''
                    
                    echo "--> Root Endpoint (/)"
                    sh 'curl -s http://localhost:3000/'
                    
                    echo "--> Health Endpoint (/health)"
                    sh 'curl -s http://localhost:3000/health'
                    
                    echo "--> API Tasks Endpoint (/api/tasks)"
                    sh 'curl -s http://localhost:3000/api/tasks'
                }
            }
        }
    }
    
    post {
        success {
            script {
                sh "echo ${IMAGE_TAG} > ${LAST_SUCCESS_FILE}"
            }
            // Removed the space between slackSend and '('
            slackSend(channel: "${SLACK_CHANNEL}", color: 'good', message: "✅ SUCCESS: Build #${BUILD_NUMBER} of ${APP_NAME} deployed successfully.\nView: ${env.BUILD_URL}")
        }
        failure {
            script {
                echo "Deployment failed. Initiating Rollback..."
                def prevTag = sh(script: "cat ${LAST_SUCCESS_FILE} || echo 'latest'", returnStdout: true).trim()
                
                echo "Rolling back to tag: ${prevTag}"
                
                docker.withRegistry("https://${DOCKER_REGISTRY}", "${DOCKER_CREDS_ID}") {
                    sh """
                        export DOCKER_REGISTRY=${DOCKER_REGISTRY}
                        export IMAGE_TAG=${prevTag}
                        docker-compose down
                        docker-compose up -d
                    """
                }
            }
            slackSend(channel: "${SLACK_CHANNEL}", color: 'danger', message: "🚨 FAILURE: Build #${BUILD_NUMBER} of ${APP_NAME} failed. Rolled back to previous stable state.\nView: ${env.BUILD_URL}")
        }
        always {
            cleanWs()
            sh 'docker image prune -f --filter "until=24h"'
        }
    }
}
