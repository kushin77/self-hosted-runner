Repository secrets and CI notes
===============================

Required repository secrets for automated image pushes and runner self-heal:

- `REGISTRY_HOST` (optional): Registry host for custom registries.
- `REGISTRY_USERNAME` / `REGISTRY_PASSWORD` or `REGISTRY_TOKEN`: Credentials used by CI to login and push images.
- `DOCKERHUB_USERNAME` / `DOCKERHUB_PASSWORD` or `DOCKERHUB_TOKEN`: Credentials for Docker Hub push.
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`: AWS credentials for ECR pushes.
- `GCP_PROJECT_ID` and `GCP_SERVICE_ACCOUNT_KEY`: Service account key JSON (base64 or raw) for Google Artifact Registry pushes.
- `DEPLOY_SSH_KEY`: SSH private key used by the self-heal workflow to run Ansible against runner hosts.
- `RUNNER_MGMT_TOKEN` (optional): Personal Access Token (PAT) with `administration:read` scope. If configured, this token is used by the `Runner Self-Heal` workflow to bypass potential `403` errors from `GITHUB_TOKEN` when listing runners. Fallback is `github.token`.

Guidance:

- The CI workflows now guard login/push steps and will skip pushes when required secrets are not set. This prevents failed runs due to empty credentials.
- If you want automated pushes in CI, add the appropriate secrets via repository Settings → Secrets and variables → Actions.
- To enable automated runner self-heal, add `DEPLOY_SSH_KEY` (private key with limited scope) and ensure `ansible/inventory` points to reachable runner hosts.

Security:

- Store secrets in GitHub Actions secrets (not in code). Use least privilege credentials and rotate regularly.

Provisioning steps (copyable commands for admins):

- Create a machine/service account (preferred) and generate a short-lived PAT with the minimal scope required. For `RUNNER_MGMT_TOKEN` the PAT should include:
	- `administration:read` (minimum)

- Add repository secrets using the GitHub CLI (examples):

	- Add `RUNNER_MGMT_TOKEN` (PAT):

		gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "<PASTE_PAT_HERE>"

	- Add `DEPLOY_SSH_KEY` (private key file):

		gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner --body-file /path/to/private_key

- Verify secrets from the repo (read-only listing):

		gh secret list --repo kushin77/self-hosted-runner

Notes:

- Use a machine/service account and avoid using personal tokens.
- Limit PAT scope and set an expiration. Record rotation steps and owners in this document.
- Once both `RUNNER_MGMT_TOKEN` and `DEPLOY_SSH_KEY` are present the automation (`secrets-health`, `self-heal-retry`, and `runner-self-heal`) will automatically dispatch remediation and post results to the configured issues.
