# Runbook: Hands-off GitLab Runner Deploy (Protected CI)

Purpose
-------
Provide operator steps to perform a fully automated, secrets-safe deployment of the Kubernetes-backed GitLab Runner using GitLab CI. This path avoids local cluster access by running the deploy job from GitLab with protected variables.

Prerequisites
-------------
- GitLab group/project Maintainer access to set protected variables
- `REG_TOKEN` (one-time runner registration token)
- `KUBECONFIG` for target cluster (base64 encoded into `KUBECONFIG_BASE64`)

Steps
-----
1. Base64-encode the kubeconfig (on a secure machine with access to the cluster):

```bash
base64 -w0 ~/.kube/config > kubeconfig.b64
# Copy the contents of kubeconfig.b64 to clipboard for GitLab CI variable
```

2. In GitLab UI (Group or Project > Settings > CI / CD > Variables):
- Add `KUBECONFIG_BASE64` (protected, masked, value = contents of kubeconfig.b64)
- Add `REG_TOKEN` (protected, masked, value = the short-lived registration token)

3. Confirm the repository includes the deploy include (already present):
The pipeline include is: `.gitlab/ci-includes/runner-deploy.gitlab-ci.yml`

4. Run the manual job in GitLab (Pipelines → Run pipeline → choose `main`, then click the manual `deploy:sovereign-runner` job). The job will:
- Install `helm` and required tooling in the job container
- Create a sealed or plain secret from `REG_TOKEN` using `scripts/ci/create_sealedsecret_from_token.sh`
- Apply the SealedSecret/Secret into the `gitlab-runner` namespace
- Run `scripts/ci/hands_off_runner_deploy.sh` to install the Helm release

5. Verify the deployment from GitLab job logs or via `kubectl`:

```bash
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=200
./scripts/ci/validate_runner_readiness.sh # run in CI or locally (requires kubeconfig)
```

6. Trigger the YAMLtest job to validate runner pick-up (from this repo include or manually):

```bash
# From CI helper (if you have API token locally):
GITLAB_API_TOKEN=<token> PROJECT_ID=<id> ./scripts/ci/trigger_yamltest_pipeline.sh main
```

Rollback
--------
- Disable the new runner in GitLab (Group > Settings > CI / Runners) or delete the Helm release:

```bash
helm uninstall gitlab-runner -n gitlab-runner
kubectl -n gitlab-runner delete secret gitlab-runner-regtoken || true
```

Notes
-----
- Use SealedSecrets in production clusters: apply `infra/gitlab-runner/sealedsecret.example.yaml` pattern and the controller will unseal on the target cluster. The job will attempt to create a SealedSecret if `kubeseal` is available in the CI image.
- Do not copy tokens into repositories or chat. Use GitLab protected variables.
