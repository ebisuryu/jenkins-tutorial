pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '14'))
        timestamps()
        timeout(time: 60, unit: 'MINUTES')
        // Serializes builds of each branch, including deployments from main.
        disableConcurrentBuilds()
    }

    environment {
        registry = 'ebisuryu/house-price-prediction-api'
        registryCredential = 'dockerhub'
    }

    stages {
        stage('Prepare') {
            steps {
                script {
                    env.RUN_ID = env.BUILD_TAG.replaceAll('[^a-zA-Z0-9_.-]', '-').toLowerCase()
                    env.IMAGE = "${env.registry}:sha-${env.GIT_COMMIT}"
                    env.TEST_IMAGE = "house-price-test:${env.RUN_ID}"
                    env.TEST_CONTAINER = "${env.RUN_ID}-tests"
                    env.SMOKE_CONTAINER = "${env.RUN_ID}-smoke"
                }
                sh 'mkdir -p reports'
            }
        }
        stage('Lint and test') {
            steps {
                sh '''
                    set -eu
                    docker build --target test -f app/Dockerfile -t "$TEST_IMAGE" .
                    docker create --name "$TEST_CONTAINER" "$TEST_IMAGE"
                    result=0
                    docker start -a "$TEST_CONTAINER" || result=$?
                    docker cp "$TEST_CONTAINER:/tmp/reports/." reports/ || result=1
                    exit "$result"
                '''
            }
            post {
                always {
                    junit testResults: 'reports/junit.xml', allowEmptyResults: true
                }
            }
        }
        stage('Build image') {
            steps {
                sh 'docker build --target production -f app/Dockerfile -t "$IMAGE" .'
            }
        }
        stage('Smoke test image') {
            steps {
                sh '''
                    set -eu
                    docker run -d --name "$SMOKE_CONTAINER" "$IMAGE"
                    docker exec -i "$SMOKE_CONTAINER" python < scripts/smoke_test.py
                '''
            }
        }
        stage('Publish') {
            when { branch 'main' }
            steps {
                script {
                    docker.withRegistry('', registryCredential) {
                        sh 'docker push "$IMAGE"'
                    }
                }
            }
        }
        stage('Deploy staging') {
            when { branch 'main' }
            steps {
                sh 'sh scripts/deploy.sh "$IMAGE" staging'
            }
        }
        stage('Approve production') {
            when { branch 'main' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Staging passed. Deploy ${env.IMAGE} to production?", ok: 'Deploy'
                }
            }
        }
        stage('Deploy production') {
            when { branch 'main' }
            steps {
                sh 'sh scripts/deploy.sh "$IMAGE" production'
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'reports/*.xml', allowEmptyArchive: true
            sh '''
                for name in "${TEST_CONTAINER:-}" "${SMOKE_CONTAINER:-}"; do
                    if [ -n "$name" ] && docker container inspect "$name" >/dev/null 2>&1; then
                        docker logs --tail 30 "$name" || true
                        docker rm -f "$name" || true
                    fi
                done
                if [ -n "${TEST_IMAGE:-}" ]; then
                    docker image rm "$TEST_IMAGE" || true
                fi
            '''
            deleteDir()
        }
    }
}
