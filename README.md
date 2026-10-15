# Jenkins Tutorial: House Price Prediction API

Use Jenkins to test a trained house price prediction model, build a Docker image for its FastAPI service, and publish the image to Docker Hub.

The main pipeline implements testing and image publishing. Its `Deploy` stage currently prints messages only. Run the published image manually using the instructions below, or extend the stage for your deployment environment.

Run all commands from the repository root unless stated otherwise.

## Prerequisites

- Git and a local checkout of this repository.
- Docker Engine with Docker Compose v2, or Docker Desktop with Compose enabled.
- Available host ports `8081` for Jenkins and `30001` for the API. Compose also publishes Jenkins agent port `50000`.
- A Git repository accessible to Jenkins and a Docker Hub account with image push permission, for the main pipeline.
- Internet access to download images, Jenkins plugins, and Python dependencies.

The Dockerfile and main pipeline use Python 3.8 with older pinned dependencies. Use the matching runtime for this tutorial; the current dependencies should not be assumed to work with newer Python versions.

## Run the API with Docker

Build and start only the API with Compose:

```shell
docker compose up -d --build app
docker compose logs --tail=100 app
```

Build and start both the API and Jenkins:

```shell
docker compose up -d --build
```

Alternatively, run the API without Compose:

```shell
docker build -f app/Dockerfile -t house-price-prediction-api:local .
docker run -d --name house-price-api -p 30001:30000 house-price-prediction-api:local
```

Choose one method at a time; both use host port `30001`.

Open [Swagger UI](http://localhost:30001/docs) to inspect the schema and try the endpoint, or send a request from a terminal:

```shell
curl --fail-with-body -X POST http://localhost:30001/predict \
  -H 'Content-Type: application/json' \
  -d '{
    "MSSubClass": 60,
    "MSZoning": "RL",
    "LotArea": 7844,
    "LotConfig": "Inside",
    "BldgType": "1Fam",
    "OverallCond": 7,
    "YearBuilt": 1978,
    "YearRemodAdd": 1978,
    "Exterior1st": "HdBoard",
    "BsmtFinSF2": 0,
    "TotalBsmtSF": 672
  }'
```

The response contains a numeric `price`. The repository test expects `157551.3761237591` for this input. Every request field has a default in `HouseInfo`, so sending `{}` uses the same sample values.

The API loads the model at startup. Its default path is resolved relative to `app/main.py`, independently of the working directory. `MODEL_PATH` overrides the default `app/models/model.pkl`; the Docker image sets it to `/app/models/model.pkl`.

For the Compose API, view logs or stop it with `docker compose logs app` and `docker compose stop app`. For the standalone Docker container:

```shell
docker logs house-price-api
docker stop house-price-api
docker rm house-price-api
```

## Run locally with Python

The pinned scikit-learn version requires Python 3.7–3.10. Use Python 3.8 to match Jenkins and Docker; ensure `.venv` uses Python 3.8 before installing these requirements.

On Apple Silicon, LightGBM 3.3.4 builds from source and needs CMake, a C++ compiler, and OpenMP. Install OpenMP with Homebrew if it is missing:

```shell
brew install libomp
```

Create and activate a Python 3.8 environment, then install the build tools before the application dependencies. CMake is kept below version 4 for the older LightGBM build scripts.

```shell
python3.8 -m venv .venv
source .venv/bin/activate
python -m pip install wheel 'cmake<4'
python -m pip install -r requirements.txt
python -m pytest
python -m uvicorn app.main:app --host 0.0.0.0 --port 30001
```

If you use `uv`, install Python 3.8 with `uv python install 3.8` if needed, then create `.venv` and install dependencies into it explicitly:

```shell
uv venv --python 3.8 .venv
source .venv/bin/activate
uv pip install --python .venv/bin/python wheel 'cmake<4'
uv pip install --python .venv/bin/python -r requirements.txt
```

Keep the API running while sending requests from another terminal. To use `app/client.py`, install its additional dependency in the same environment:

```shell
python -m pip install requests
python app/client.py
```

`requests` is not included in `app/requirements.txt`. The existing test exercises the saved model directly; it does not test the HTTP endpoint or deployment.

## Start Jenkins

```shell
docker compose up -d --build jenkins
docker compose ps
docker compose logs --tail=100 jenkins
```

Open [Jenkins](http://localhost:8081). On first startup, retrieve the unlock password:

```shell
docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Enter the password, install the suggested plugins, and create an administrator account. The password above unlocks initial setup; use your new account for subsequent sign-ins.

Compose builds `jenkins/Dockerfile` from `jenkins/jenkins:lts-jdk21`, adding Docker CLI, Buildx, and the Pipeline, Git, Docker Pipeline, and Timestamper plugins. The `jenkins_home` named volume preserves configuration, plugins, credentials, and jobs across container restarts.

This local configuration runs Jenkins as root and mounts `/var/run/docker.sock`. Jobs using that socket can control the host Docker daemon. Use it for trusted tutorial jobs; privileged mode is not required.

## Prepare Jenkins for Docker builds

Under **Manage Jenkins → Plugins**, ensure these plugins are installed:

| Plugin | Used for |
| --- | --- |
| Pipeline | Running the pipeline scripts. |
| Git | Checking out the repository. |
| Docker Pipeline | The Docker agent, `docker.build`, and `docker.withRegistry`. |
| Timestamper | The `timestamps()` option. |

The custom Jenkins image includes Docker CLI and the plugins above. Compose mounts the host socket to provide access to the Docker daemon. Ensure Docker Engine or Docker Desktop is running before starting Jenkins.

For jobs running inside the Jenkins container, check both:

```shell
docker compose exec jenkins docker --version
docker compose exec jenkins docker info
docker compose exec jenkins docker run --rm hello-world
```

After changing `jenkins/Dockerfile`, run `docker compose up -d --build jenkins` to rebuild and recreate Jenkins while retaining its named volume. See the official [Jenkins Docker installation guide](https://www.jenkins.io/doc/book/installing/docker/) for image customization and [Using Docker with Pipeline](https://www.jenkins.io/doc/book/pipeline/docker/) for execution requirements.

The main pipeline uses `agent any`, so ensure all eligible nodes have the required tools, or assign a suitable agent label. Complete this setup before running the main pipeline. Use `jenkins/docker-python.Jenkinsfile` to verify Docker Pipeline by running Python in a container. `jenkins/parallel.Jenkinsfile` only prints messages and does not require Docker.

## Configure Docker Hub credentials

Create a Docker Hub repository for the application. In `Jenkinsfile`, replace the sample image repository with your own:

```groovy
environment {
    registry = 'YOUR_DOCKERHUB_USERNAME/house-price-prediction-api'
    registryCredential = 'dockerhub'
}
```

In **Manage Jenkins → Credentials**, add a credential available to the job:

- **Kind:** Username with password.
- **Username:** Your Docker Hub username.
- **Password:** Your Docker Hub access token.
- **ID:** `dockerhub`, matching `registryCredential`.

Commit the repository-name change to the branch Jenkins will check out. Store the token in Jenkins credentials.

## Create and run a pipeline job

Push the repository, including the model artifact and pipeline files, to a Git remote Jenkins can access. Then configure a job:

1. Select **New Item**, enter a name, choose **Pipeline**, and click **OK**.
2. Set **Definition** to **Pipeline script from SCM**.
3. Choose **Git**, enter the repository URL, and select checkout credentials if the repository is private.
4. Set the branch specifier to your branch, such as `*/main`.
5. Set **Script Path** to one of the files below and save.
6. Select **Build Now** and inspect the build's **Console Output**.

| Script Path | Behavior |
| --- | --- |
| `jenkins/docker-python.Jenkinsfile` | Verifies Python runs in Docker, prints Test and Build messages, then waits for approval before the Deploy message. |
| `jenkins/parallel.Jenkinsfile` | Runs `test1` and `test2` in parallel, followed by Build and Deploy messages. |
| `Jenkinsfile` | Runs the model test in `python:3.8`, builds the API image, and pushes it to Docker Hub. |

The main pipeline retains up to five builds and applies a five-day retention limit. It publishes `<registry>:<BUILD_NUMBER>` and `<registry>:latest`. A successful build does not start the API: the Deploy stage only prints messages.

### Trigger builds after repository changes

Pushing code alone does not trigger a build with the current Jenkinsfile. Configure a job trigger:

- For local Jenkins, enable **Poll SCM** with a schedule such as `H/5 * * * *` to check for changes approximately every five minutes.
- For GitHub webhooks, install the GitHub plugin, enable **GitHub hook trigger for GITScm polling**, and configure the repository webhook to send push events to `https://YOUR_REACHABLE_JENKINS_URL/github-webhook/`. GitHub must be able to reach this URL; `localhost:8081` is only accessible locally.

See the official [Pipeline SCM documentation](https://plugins.jenkins.io/workflow-scm-step/) for polling behavior.

## Run an image published by Jenkins

After the main pipeline succeeds, substitute your repository name and Jenkins build number:

```shell
docker pull YOUR_DOCKERHUB_USERNAME/house-price-prediction-api:BUILD_NUMBER
docker run -d --name house-price-api -p 30001:30000 \
  YOUR_DOCKERHUB_USERNAME/house-price-prediction-api:BUILD_NUMBER
```

Stop and remove any existing `house-price-api` container first using the commands above. Open `http://localhost:30001/docs` or repeat the sample request to verify the running service.

## Explore model training

The notebook covers data exploration, preprocessing, a linear regression baseline, LightGBM training, and evaluation. Run it with `notebooks/` as the working directory so its `../data` and `../app/models` paths resolve correctly.

Notebook dependencies such as Jupyter, `openpyxl`, Matplotlib, and Seaborn are additional to the API requirements. The export cell removes and recreates `../app/models` before saving `model.pkl`; review that cell before running it. Retraining may change predictions, so review the test's fixed expected value before committing a replacement artifact.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| Jenkins is unavailable at `localhost:8081` | Check `docker compose ps`, Jenkins logs, and whether port `8081` is already in use. |
| `docker: not found` in Jenkins | Install the CLI in the execution environment; the socket mount and Docker Pipeline plugin do not install it. |
| Jenkins cannot connect to Docker | Check that the host daemon is running and the execution node can access its configured socket. Run `docker info` on that node. |
| Jenkins rejects the Docker agent or cannot resolve `docker` | Install Docker Pipeline and restart Jenkins if prompted. |
| Docker Hub push is denied | Verify the `dockerhub` credential, token permissions, and repository namespace. |
| Dependencies fail to install with a newer Python version | Use the Python 3.8 runtime used by the Dockerfile and pipeline. |
| The model cannot be loaded | Check `app/models/model.pkl`, `MODEL_PATH`, the working directory, and compatibility with the saved model's library versions. |
| The prediction test fails after retraining | Compare the new artifact and prediction with the test's exact expected value. |
| API requests fail on port `30001` | Check logs and the `30001:30000` mapping; the container listens on `30000`. |
| A Git push does not start Jenkins | Configure polling or a reachable webhook and confirm the job uses the intended branch. |

## Stop Jenkins

```shell
docker compose down
```

This removes the Compose containers while retaining the named volume. Adding `--volumes` also deletes stored Jenkins configuration, credentials, and jobs.
