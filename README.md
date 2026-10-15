# Jenkins Tutorial: House Price Prediction API

Use Jenkins to test a trained house price prediction model, build a Docker image for its FastAPI service, and publish the image to Docker Hub.

The Multibranch Pipeline runs model tests for pull requests. On `main`, it also builds and publishes the image, then replaces the local `house-price-api` container on port `30001`.

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

The main pipeline retains up to five builds and applies a five-day retention limit. It publishes `<registry>:<BUILD_NUMBER>` and `<registry>:latest`. In a Multibranch Pipeline, the Build and Deploy stages run only on `main`; Deploy replaces the local `house-price-api` container using the build-number image tag.

## Automatically test pull requests

Use a **Multibranch Pipeline** with GitHub Branch Source for pull request discovery. The separate Pipeline jobs above are useful for manual examples.

### 1. Configure GitHub credentials and fix status reporting

A build can succeed in Jenkins while GitHub shows no result. If Jenkins logs `Could not update commit status` with HTTP `403` and `Resource not accessible by personal access token`, update the token used by `github-credentials`:

1. In GitHub, open **Settings → Developer settings → Personal access tokens → Fine-grained tokens**.
2. Edit the token used by Jenkins, or generate a replacement. Select resource owner `ebisuryu` and grant access to `jenkins-tutorial`.
3. Set these repository permissions:

   | Permission | Access |
   | --- | --- |
   | Contents | Read-only |
   | Pull requests | Read-only |
   | Metadata | Read-only (automatically included) |
   | Commit statuses | Read and write |

4. Save the permissions. If replacing the token, copy it directly into Jenkins: **Manage Jenkins → Credentials → System → Global credentials → github-credentials → Update**. Use **Username with password**, username `ebisuryu`, and the token as the password. Keep ID `github-credentials`.
5. In the Multibranch job, confirm **Branch Sources → GitHub → Credentials** selects `github-credentials`.
6. Rerun the PR build and confirm the commit status appears on GitHub. Existing completed builds are not automatically republished when token permissions change.

These GitHub credentials are separate from the `dockerhub` credentials used to publish images. See [GitHub token permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

### 2. Configure the Multibranch job

1. Install **GitHub Branch Source** under **Manage Jenkins → Plugins**.
2. Create **New Item → Multibranch Pipeline**, or configure the existing **Multibranch Pipeline** job.
3. Under **Branch Sources → GitHub**, select `github-credentials`, owner `ebisuryu`, and repository `jenkins-tutorial`.
4. Under **Behaviours**, enable **Discover branches**. To avoid testing the same commit as both a source branch and a PR, choose the option that excludes branches also filed as PRs.
5. Enable **Discover pull requests from origin**. Choose the strategy that tests the PR merged with its current target branch.
6. Under **Build Configuration**, set **Script Path** to `Jenkinsfile` and save.

See [Jenkins Multibranch Pipeline documentation](https://www.jenkins.io/doc/book/pipeline/multibranch/).

### 3. Start ngrok and configure the webhook

1. Start Jenkins:

   ```shell
   docker compose up -d --build jenkins
   ```

2. In another terminal, start ngrok and keep it running:

   ```shell
   ngrok http 8081
   ```

3. In GitHub, open **ebisuryu/jenkins-tutorial → Settings → Webhooks**. Edit the existing Jenkins webhook, or add one if absent.
4. Set **Payload URL** to the HTTPS URL printed by ngrok followed by `/github-webhook/`, for example:

   ```text
   https://clamor-exploring-jellied.ngrok-free.dev/github-webhook/
   ```

5. Set **Content type** to `application/json`, select **Pull requests** and **Pushes** events, and keep the webhook active.
6. Check **Recent Deliveries** for HTTP `200`. The Jenkins homepage alone is not the webhook endpoint. Update the webhook if your ngrok URL changes.
7. In Jenkins, select **Scan Multibranch Pipeline Now** once to discover existing branches and PRs.

### 4. Create a test pull request yourself

First review the existing [PR #1](https://github.com/ebisuryu/jenkins-tutorial/pull/1). It adds `reuseNode true` to the Docker test agent and limits Build and Deploy to `main`. Merge that change before following the commands below if it has not already been merged. Merging to `main` can trigger image publishing and local deployment; stop the Compose API first if it occupies port `30001`:

```shell
docker compose stop app
```

With a clean working tree, update `main` and create a new branch from it:

```shell
git switch main
git pull --ff-only origin main
git switch -c test/jenkins-pr-webhook
```

Make a small documentation change, commit it, and push:

```shell
printf '\n<!-- Jenkins PR webhook test -->\n' >> README.md
git add README.md
git commit -m "docs: verify Jenkins pull request webhook"
git push -u origin test/jenkins-pr-webhook
```

Open [the repository](https://github.com/ebisuryu/jenkins-tutorial), select **Compare & pull request**, choose base `main` and compare `test/jenkins-pr-webhook`, then select **Create pull request**.

Alternatively, if GitHub CLI is authenticated:

```shell
gh pr create --repo ebisuryu/jenkins-tutorial \
  --base main --head test/jenkins-pr-webhook \
  --title "docs: verify Jenkins pull request webhook" \
  --body "Verify that opening a pull request automatically triggers the Jenkins model test."
```

Use a new branch name if `test/jenkins-pr-webhook` already exists. You can close the test PR without merging it after verification.

### 5. Verify the automatic build

1. In GitHub **Webhooks → Recent Deliveries**, confirm the `pull_request` event with action `opened` received HTTP `200`.
2. Open Jenkins **Multibranch Pipeline → PR-<number> → latest build → Console Output**.
3. Confirm checkout ran, the test reports `1 passed`, and the build ends with `Finished: SUCCESS`.
4. On a PR, Build and Deploy should show `skipped due to when conditional`.
5. Check the GitHub PR for the Jenkins status. If it is absent while Jenkins succeeded, repeat the credential-permission steps above.

To test rebuilding an existing PR, commit another small change to its source branch and push. No manual **Build Now** should be needed. A successful webhook response confirms receipt; the Jenkins build log confirms execution.

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
