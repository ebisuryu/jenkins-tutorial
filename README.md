# Jenkins Tutorial: House Price Prediction API

A practical CI/CD tutorial for a FastAPI house price prediction service. Build a Jenkins Multibranch Pipeline that validates pull requests, publishes Docker images, and deploys through staging and manual production approval.

```text
Pull request → Checkout → Lint + tests → Build image → Smoke test
main         → Same checks → Publish → Deploy staging → Approve → Deploy production
```

Staging and production run on the same Docker daemon as Jenkins. Production requires manual approval, so this workflow implements Continuous Delivery. All commands below run from the repository root unless stated otherwise.

| Service | Container | Host URL |
| --- | --- | --- |
| Jenkins | `jenkins` | http://localhost:8081 |
| Staging API | `house-price-api-staging` | http://localhost:30002/docs |
| Production API | `house-price-api` | http://localhost:30001/docs |

## 1. Prepare the repository and Docker

You need Git, Docker Engine with Compose v2 or Docker Desktop, an installed and authenticated ngrok client, and GitHub and Docker Hub accounts. GitHub CLI (`gh`) is optional.

Fork [this repository](https://github.com/ebisuryu/jenkins-tutorial) into your GitHub account so you can push branches, manage webhooks, and merge pull requests. Clone your fork:

```shell
git clone https://github.com/YOUR_GITHUB_USERNAME/jenkins-tutorial.git
cd jenkins-tutorial
```

Replace placeholders throughout this guide before running commands:

| Placeholder | Replace with |
| --- | --- |
| `YOUR_GITHUB_USERNAME` | The GitHub account or organization that owns your repository |
| `YOUR_DOCKERHUB_USERNAME` | Your Docker Hub namespace with image push permission |
| `YOUR-NGROK-DOMAIN` | The current public HTTPS domain printed by ngrok |
| `REPLACE_WITH_FULL_COMMIT_SHA` | The full commit SHA from a successful `main` build |

If you maintain the original repository, use `ebisuryu` as its owner. If you renamed your fork, also replace `jenkins-tutorial` in GitHub commands and job configuration.

Verify Docker and Compose:

```shell
docker version
docker compose version
docker compose config --quiet
```

Keep host ports `8081`, `30002`, and `30001` available for Jenkins, staging, and production. Compose also publishes Jenkins agent port `50000`.

Use the bundled `models/model.pkl`. The image and dependencies use Python 3.8 to match the saved model. One `requirements.txt` contains both application dependencies and test/lint tools.

## 2. Start and sign in to Jenkins

Start only Jenkins for the CI/CD walkthrough. The pipeline will create the API containers later.

```shell
docker compose up -d --build jenkins
docker compose ps
docker compose logs --tail=100 jenkins
```

Open [Jenkins](http://localhost:8081). For a new installation, retrieve the initial password:

```shell
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Unlock Jenkins, install the suggested plugins, and create an administrator account. For an existing installation, sign in with the account you previously created. The file contains the initial setup password; it does not reveal a password changed after setup.

The custom `jenkins/Dockerfile` installs Docker CLI, Buildx, Pipeline, Git, GitHub Branch Source, Docker Pipeline, Timestamper, and JUnit. Verify Docker access inside Jenkins:

```shell
docker compose exec jenkins docker version
docker compose exec jenkins docker run --rm hello-world
```

Both client and server information should appear in `docker version`; `hello-world` should finish successfully. If an existing Jenkins volume is missing a plugin, install it under **Manage Jenkins → Plugins** and restart when prompted, after active builds finish.

The `jenkins_home` volume preserves users, credentials, plugins, and jobs. This local setup runs Jenkins as root with the host Docker socket mounted; use it for trusted tutorial jobs.

## 3. Configure the Jenkins URL

Choose one address for browser access and set **Manage Jenkins → System → Jenkins Location → Jenkins URL** to that address.

For this local walkthrough, use:

```text
http://localhost:8081/
```

Keep using that address when signing in and approving builds. Jenkins uses its configured URL in generated links, including Deploy/Abort links in console logs.

The GitHub webhook will use a public ngrok URL in step 5; it can differ from your browser address. Build links published to GitHub will use the configured Jenkins URL, so localhost links are accessible only on your machine. If you need remotely accessible build links, use the current ngrok HTTPS address as Jenkins URL and access the UI through that same address.

## 4. Add credentials and set the image repository

### Docker Hub

Create a Docker Hub repository named `house-price-prediction-api`. The current `Jenkinsfile` uses `ebisuryu/house-price-prediction-api`; change `registry` if publishing under another account:

```groovy
environment {
    registry = 'YOUR_DOCKERHUB_USERNAME/house-price-prediction-api'
    registryCredential = 'dockerhub'
}
```

In **Manage Jenkins → Credentials → System → Global credentials**, add:

| Field | Value |
| --- | --- |
| Kind | Username with password |
| Username | Your Docker Hub username |
| Password | Your Docker Hub access token |
| ID | `dockerhub` |

Commit and push any repository-name change to the branch Jenkins will build. Store tokens only in Jenkins credentials.

### GitHub

Create a fine-grained personal access token for the repository owner and select this repository. Grant these repository permissions:

| Permission | Access |
| --- | --- |
| Contents | Read-only |
| Pull requests | Read-only |
| Metadata | Read-only, automatically included |
| Commit statuses | Read and write |

Add another **Username with password** credential in Jenkins: your GitHub username, the token as its password, and ID `github-credentials`.

The Docker Hub and GitHub credentials serve different services. The GitHub token above is for repository discovery and status reporting; configure the webhook manually in the next step. See [GitHub token permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

## 5. Connect GitHub to Jenkins with a webhook

Start ngrok in another terminal and keep it running:

```shell
ngrok http 8081
```

Copy the current public HTTPS URL from ngrok. In **GitHub repository → Settings → Webhooks → Add webhook**, configure:

| Setting | Value |
| --- | --- |
| Payload URL | Your current ngrok HTTPS URL followed by `/github-webhook/` |
| Content type | `application/json` |
| Events | Let me select individual events → **Pushes** and **Pull requests** |
| Active | Enabled |

For example, replace `YOUR-NGROK-DOMAIN` below with the domain ngrok actually assigned:

```text
https://YOUR-NGROK-DOMAIN/github-webhook/
```

Check **Recent Deliveries** after adding the webhook or creating a PR. A successful delivery returns HTTP `200`. If ngrok stops or its domain changes, restart the tunnel, update the webhook URL, and redeliver the failed event. The Jenkins homepage alone is not the webhook endpoint.

## 6. Create the Multibranch Pipeline

Before saving the job, complete the credentials above and ensure ports `30002` and `30001` are available. Saving can immediately discover and run `main`, which publishes an image and deploys staging; production still waits for approval.

If you previously started the optional Compose API, stop it to free port `30001`:

```shell
docker compose stop app
```

1. Select **New Item → Multibranch Pipeline**. For this guide, use the name `Multibranch Pipeline`, or reuse your existing job.
2. Under **Branch Sources → Add source → GitHub**, select `github-credentials`.
3. Set owner to `YOUR_GITHUB_USERNAME` and repository to `jenkins-tutorial`, or the name of your fork.
4. Under **Behaviours → Discover branches**, select the strategy that excludes branches also filed as PRs.
5. Enable **Discover pull requests from origin** and select the strategy that tests the PR merged with its current target branch.
6. Under **Build Configuration**, set **Script Path** to `Jenkinsfile`.
7. Save, then use **Scan Multibranch Pipeline Now** if discovery has not started.

Branches must contain `Jenkinsfile`. PR jobs appear as `PR-<number>`. Use the Multibranch job for the main CI/CD workflow: its `branch 'main'` conditions depend on branch metadata. The standalone demo jobs are described at the end of this guide.

The pipeline uses `agent any`; the execution node must have Git, a POSIX shell, Docker CLI, and access to the Docker daemon. This walkthrough executes on the Jenkins container. See [Jenkins Multibranch Pipeline documentation](https://www.jenkins.io/doc/book/pipeline/multibranch/).

## 7. Create a PR and verify CI

From a clean working tree, create a new branch from the current remote `main`:

```shell
git switch main
git pull --ff-only origin main
git switch -c test/cicd-check
printf '\n<!-- CI webhook check -->\n' >> README.md
git add README.md
git commit -m "docs: verify Jenkins CI webhook"
git push -u origin test/cicd-check
```

Choose a different branch name if `test/cicd-check` already exists. On GitHub, create a PR with base `main` and compare `test/cicd-check`. Alternatively, with an authenticated GitHub CLI:

```shell
gh pr create --repo YOUR_GITHUB_USERNAME/jenkins-tutorial \
  --base main --head test/cicd-check \
  --title "docs: verify Jenkins CI webhook" \
  --body "Verify lint, model/API tests, image build, and container smoke test."
```

Verify the following:

1. GitHub **Webhooks → Recent Deliveries** shows `pull_request`, action `opened`, with HTTP `200`.
2. Jenkins creates `Multibranch Pipeline → PR-<number>`.
3. Open the build's **Console Output**. Lint, all six tests, the production image build, and the image smoke test should pass.
4. **Publish**, **Deploy staging**, **Approve production**, and **Deploy production** are skipped for a PR.
5. The build ends with `Finished: SUCCESS`, and GitHub shows the Jenkins status. JUnit results are available from the build's test report; the XML is also archived.

Push another commit to the same branch to verify automatic rebuilding. A webhook `200` confirms receipt; a successful Jenkins build confirms execution. **Scan Multibranch Pipeline Now** can discover an existing PR if an event was missed, but it does not repair a broken webhook.

In GitHub branch protection or rulesets, require the Jenkins status check shown by a successful PR build before merging into `main`.

## 8. Merge, review staging, and approve production

Merge the PR on GitHub after its checks pass. The `main` build runs these stages:

| Stage | Action |
| --- | --- |
| Prepare | Generate image and temporary container names after the default SCM checkout |
| Lint and test | Run Ruff and six model/API tests in the Docker `test` target |
| Build image | Build the `production` target |
| Smoke test image | Check `/health` and a known `/predict` result in an isolated container |
| Publish | Push `<registry>:sha-<full-commit-sha>` to Docker Hub |
| Deploy staging | Replace `house-price-api-staging` on port `30002` and smoke test it |
| Approve production | Wait up to thirty minutes for a decision |
| Deploy production | Replace `house-price-api` on port `30001` and smoke test it |

Staging and production use the same local image that passed the image smoke test; it is not rebuilt between deployments. Use the image tag printed by the successful `main` build when identifying a release.

When **Approve production** is waiting:

1. Check staging at [Swagger UI](http://localhost:30002/docs) and run:

   ```shell
   curl --fail http://localhost:30002/health
   curl --fail -X POST http://localhost:30002/predict \
     -H 'Content-Type: application/json' -d '{}'
   ```

2. Open **Multibranch Pipeline → main → current build → Input / Paused for Input**. You can also append `/input/` to that build's URL. For build number `N`, the local URL is:

   ```text
   http://localhost:8081/job/Multibranch%20Pipeline/job/main/N/input/
   ```

3. Sign in and select **Deploy** to continue, or **Abort** to cancel the build. Aborting or letting approval expire leaves the deployed staging version and existing production version in place.
4. After selecting **Deploy**, wait for `Finished: SUCCESS`, then verify production:

   ```shell
   curl --fail http://localhost:30001/health
   curl --fail -X POST http://localhost:30001/predict \
     -H 'Content-Type: application/json' -d '{}'
   docker ps --filter name=house-price-api
   ```

`/health` should return `{"status":"ok","model_loaded":true}`. The default prediction is approximately `157551.3761237591`. Every request field has a default, so `{}` uses the sample house input. See [Jenkins Input Step](https://www.jenkins.io/doc/pipeline/steps/pipeline-input-step/) for the approval interaction.

If console Deploy/Abort links do not respond, open the build's Input page directly on the address where you are signed in. Console links can point to the configured Jenkins URL even when you opened the UI elsewhere. Changing Jenkins URL does not rewrite links already recorded in an older build log.

The pipeline keeps up to ten builds for up to fourteen days, archives JUnit XML, and cleans temporary test/smoke containers and its workspace in `post`. Runs of each branch are serialized; a waiting `main` approval blocks later `main` builds. The overall pipeline timeout is sixty minutes.

## 9. Roll back a release

`scripts/deploy.sh` renames the existing container to `<name>-rollback`, stops it, starts the candidate, and checks `/health` and `/predict`. If the deployment fails or receives a handled termination signal, it removes the candidate and restarts the previous container with its original configuration. The Jenkins build still reports failure. If no previous container exists, the failed candidate is removed.

After success, the previous container is removed; its image is retained. Replacement causes a short outage. A host crash or forced kill can leave a `-rollback` container, and the script refuses to overwrite that recovery state. Inspect both containers and restore or resolve the interrupted rollout before retrying.

To deploy an older published release manually, copy its full image tag from a previous successful `main` build. Run this on the same Docker host as the application, after any active deployment has finished:

```shell
IMAGE='YOUR_DOCKERHUB_USERNAME/house-price-prediction-api:sha-REPLACE_WITH_FULL_COMMIT_SHA'
docker pull "$IMAGE"
sh scripts/deploy.sh "$IMAGE" staging
# Verify staging before replacing production:
sh scripts/deploy.sh "$IMAGE" production
```

Use your configured registry namespace if different, and run `docker login` first if the image requires authentication. Manual deployment runs outside Jenkins and does not have its approval gate.

## Optional: run and test without Jenkins

### Docker

Run the same lint and tests as CI:

```shell
docker build --target test -f app/Dockerfile -t house-price-ci:local .
docker run --rm house-price-ci:local
```

Both Docker targets install the shared `requirements.txt`. The `test` target additionally copies tests, scripts, and tool configuration. The default `production` target runs the API as `appuser` and includes a Docker health check. Build from the repository root because the Dockerfile copies root `requirements.txt` and `models/`.

For an independent API demo, when production is not using port `30001`:

```shell
docker compose up -d --build app
curl --fail http://localhost:30001/health
docker compose logs --tail=100 app
# Before returning to pipeline-managed production:
docker compose stop app
```

Wait for startup before sending the request. Do not start the Compose `app` alongside the pipeline-managed production container; both use `30001`.

### Python 3.8

Use a Python 3.8 environment to match the image and saved model. On Apple Silicon, LightGBM may need a compiler, CMake, and OpenMP; install `libomp` with Homebrew if needed.

```shell
python3.8 -m venv .venv
source .venv/bin/activate
python -m pip install wheel 'cmake<4'
python -m pip install -r requirements.txt
ruff check app tests scripts
python -m pytest -q --junitxml=reports/junit.xml
python -m uvicorn app.main:app --host 0.0.0.0 --port 30003
```

If you use `uv` to manage Python, create the environment and install dependencies with:

```shell
uv python install 3.8
uv venv --python 3.8 .venv
uv pip install --python .venv/bin/python wheel 'cmake<4'
uv pip install --python .venv/bin/python -r requirements.txt
source .venv/bin/activate
ruff check app tests scripts
python -m pytest -q --junitxml=reports/junit.xml
python -m uvicorn app.main:app --host 0.0.0.0 --port 30003
```

The direct Python demo uses `30003` so it can coexist with pipeline-managed staging and production. Send requests to `http://localhost:30003/predict` or open `/docs`. The model defaults to root `models/model.pkl`; `MODEL_PATH` overrides it. Docker sets `MODEL_PATH=/app/models/model.pkl`.

`app/client.py` is an optional client hardcoded to port `30001` and requires `requests`, which is not included in `requirements.txt`. Install it separately with `python -m pip install requests` if using that client.

### Standalone Jenkins demo jobs

These examples are separate from the Multibranch workflow:

| Script Path | Behavior |
| --- | --- |
| `jenkins/docker-python.Jenkinsfile` | Runs Python in Docker, prints Test/Build messages, and waits for approval before its Deploy message |
| `jenkins/parallel.Jenkinsfile` | Prints two parallel test messages, then Build/Deploy messages |

Create **New Item → Pipeline**, select **Pipeline script from SCM**, choose Git and this repository, set your branch (for example `*/main`), and enter one of the Script Paths above. Save and select **Build Now**. These demos do not publish or deploy the API.

### Model training

Run `notebooks/house_price_prediction.ipynb` with `notebooks/` as the working directory. It reads `../data/house_price_prediction.xlsx` and currently exports to `../app/models/model.pkl`, removing that export directory before saving. The application consumes root `models/model.pkl`; review and copy a retrained artifact there deliberately, then update the expected prediction in the tests and smoke test together.

Jupyter, `openpyxl`, Matplotlib, and Seaborn are optional training dependencies not included in the application requirements.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| Cannot sign in as `admin` | The initial password command in step 2 only retrieves the setup password; use your saved account/password if changed |
| Jenkins is unavailable on `8081` | Check Docker, `docker compose ps`, and `docker compose logs --tail=100 jenkins` |
| `docker: not found` or daemon access denied | Rebuild the custom Jenkins service and repeat the in-container Docker checks in step 2 |
| PR does not trigger a build | Keep ngrok running; verify the current `/github-webhook/` URL, Pull requests event, and delivery status; redeliver if needed |
| Webhook returns `404` | Check that the ngrok domain is current and forwards to `8081`, and that the path is `/github-webhook/` |
| Webhook returns `200` but no PR job appears | Check GitHub Branch Source credentials, PR discovery behaviour, and the branch indexing log |
| GitHub status is missing or says `Resource not accessible by personal access token` | Grant `github-credentials` Commit statuses Read and write permission and rerun the build; old results are not republished automatically |
| Docker Hub push is denied | Verify `registry`, the `dockerhub` credential, token permission, and repository ownership |
| Deploy/Abort in the console does nothing | Use the current build's `/input/` page; align the UI address with Jenkins URL and sign in there |
| No approval is available | Open the current `main` build; PR builds skip approval, and completed/expired builds cannot be approved |
| Later `main` builds are waiting | Finish or abort the existing approval; `disableConcurrentBuilds()` serializes this branch |
| Port `30001` or `30002` is already allocated | Identify the owner with `docker ps`; stop the optional Compose API if it occupies `30001` |
| Deployment refuses an existing `-rollback` container | Inspect recovery state from an interrupted deployment before retrying |
| Model loading or predictions fail | Verify `models/model.pkl`, `MODEL_PATH`, Python/ML dependency compatibility, and expected prediction values |

## Stop the tutorial services

Stop Jenkins while retaining its data:

```shell
docker compose stop jenkins
```

Stop the tunnel with Ctrl+C in its terminal. Pipeline-created API containers are independent of Compose; stop each one that exists when you no longer need it:

```shell
docker stop house-price-api-staging
docker stop house-price-api
```

`docker compose down` removes Compose services while retaining the Jenkins volume; it does not remove the pipeline-created API containers. Adding `--volumes` also deletes the stored Jenkins configuration, credentials, and jobs.
