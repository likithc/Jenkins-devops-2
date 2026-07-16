pipeline {
    agent any
    
    environment {
        APP_NAME = 'task-tracker'
        IMAGE_TAG = "${BUILD_NUMBER}"
        
        // Docker Hub Configuration
        DOCKER_REGISTRY = 'https://index.docker.io/v1/' 
        APP_IMAGE = "likithc/${APP_NAME}" 
        DOCKER_CREDS_ID = 'dockerhub'
        
        SLACK_CHANNEL = '#devops-alerts'
        LAST_SUCCESS_FILE = "/tmp/${APP_NAME}_last_success.txt"
    }
    
    tools {
        nodejs 'NodeJS_20' 
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Install Dependencies and Run Tests') {
            steps {
                // Hardened approach: Explicitly invoke the NodeJS plugin context
                script {
                    nodejs('NodeJS_20') {
                        sh 'npm install'
                        sh 'npm test'
                    }
                }
            }
        }
        
        stage('Build & Push Docker Image') {
            steps {
                script {
                    docker.withRegistry("${env.DOCKER_REGISTRY}", "${env.DOCKER_CREDS_ID}") {
                        def customImage = docker.build("${env.APP_IMAGE}:${env.IMAGE_TAG}", "--build-arg BUILDKIT_INLINE_CACHE=1 .")
                        customImage.push()
                        customImage.push("latest") 
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
                sh "echo ${env.IMAGE_TAG} > ${env.LAST_SUCCESS_FILE}"
            }
            slackSend(channel: "${env.SLACK_CHANNEL}", color: 'good', message: "✅ SUCCESS: Build #${env.BUILD_NUMBER} of ${env.APP_NAME} deployed successfully.\nView: ${env.BUILD_URL}")
        }
        failure {
            script {
                echo "Deployment failed. Initiating Rollback..."
                def prevTag = sh(script: "cat ${env.LAST_SUCCESS_FILE} || echo 'latest'", returnStdout: true).trim()
                
                echo "Rolling back to tag: ${prevTag}"
                
                docker.withRegistry("${env.DOCKER_REGISTRY}", "${env.DOCKER_CREDS_ID}") {
                    sh """
                        export DOCKER_REGISTRY='' 
                        export APP_IMAGE=${env.APP_IMAGE}
                        export IMAGE_TAG=${prevTag}
                        docker-compose down
                        docker-compose up -d
                    """
                }
            }
            slackSend(channel: "${env.SLACK_CHANNEL}", color: 'danger', message: "🚨 FAILURE: Build #${env.BUILD_NUMBER} of ${env.APP_NAME} failed. Rolled back to previous stable state.\nView: ${env.BUILD_URL}")
        }
        always {
            // Docker cleanup is safe here
            sh 'docker image prune -f --filter "until=24h"'
        }
        cleanup {
            // Moved to 'cleanup' stage to ensure files exist during rollback blocks
            cleanWs()
        }
    }
}
