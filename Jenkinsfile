pipeline {
    agent any

    options{
        // Max number of build logs to keep and days to keep
        buildDiscarder(logRotator(numToKeepStr: '5', daysToKeepStr: '5'))
        // Enable timestamp at each job in the pipeline
        timestamps()
    }

    environment{
        registry = 'ebisuryu/house-price-prediction-api'
        registryCredential = 'dockerhub'      
    }

    stages {
        stage('Test') {
            agent {
                docker {
                    image 'python:3.8' 
                }
            }
            steps {
                echo 'Testing model correctness..'
                sh 'pip install -r requirements.txt && pytest'
            }
        }
        stage('Build') {
            steps {
                script {
                    echo 'Building image for deployment..'
                    dockerImage = docker.build(registry + ":$BUILD_NUMBER", "-f app/Dockerfile .")
                    echo 'Pushing image to dockerhub..'
                    docker.withRegistry( '', registryCredential ) {
                        dockerImage.push()
                        dockerImage.push('latest')
                    }
                }
            }
        }
        stage('Deploy') {
            steps {
                script {
                    docker.withRegistry('', registryCredential) {
                        sh '''
                            set -eu

                            IMAGE="$registry:$BUILD_NUMBER"
                            docker pull "$IMAGE"

                            if docker container inspect house-price-api >/dev/null 2>&1; then
                                docker rm -f house-price-api
                            fi

                            docker run -d \
                                --name house-price-api \
                                --restart unless-stopped \
                                -p 30001:30000 \
                                "$IMAGE"
                        '''
                    }
                }
            }
        }
    }
}
