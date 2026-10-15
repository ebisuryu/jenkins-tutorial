pipeline {
    // Any available agent ip:port or an docker image
    agent any

    stages {
        stage('Test') {
            steps {
                parallel(
                    test1: {
                        echo 'Testing something 1..'
                    },
                    test2: {
                        echo 'Testing something 2..'
                    }, 
                )
                
            }
        }
        stage('Build') {
            steps {
                echo 'Building something..'

            }
        }
        stage('Deploy') {
            steps {
                // A box will be displayed to show whether to proceed 
                // with the deployment
                // input 'Do you approve deployment?'
                echo 'Deploying something..'
            }
        }
    }
}