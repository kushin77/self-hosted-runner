## Repository Secrets Runbook

This runbook describes how to provision and manage repository secrets required by automation workflows in this repository.

Important: Use a machine/service account (not a personal account) for any automation tokens. Limit scopes to the minimum required and set expirations.

Required secrets
1. `RUNNER_MGMT_TOKEN`
   - Purpose: Personal Access Token (PAT) used by automation to manage self-hosted runners and perform read/admin operations.
   - Recommendation: Create a machine account (e.g., `automation-bot@org`) and generate a PAT with minimal scopes. Prefer short-lived tokens and rotate regularly.
   - Suggested scopes: `repo` (only if needed), `admin:org` or `administration:read` where supported. Do NOT grant broad admin rights unless necessary.

2. `DEPLOY_SSH_KEY`
   - Purpose: Private SSH key used by automation to SSH into runner hosts for remediation and deployment tasks.
   - Recommendation: Generate an SSH keypair dedicated to automation, restrict the public key to the runner hosts' `authorized_keys`, and store the private key as a repository secret.

Optional secrets for DR workflows
- `GCP_SERVICE_ACCOUNT_KEY` (JSON blob)
- `GCP_PROJECT_ID`

Add repository secret (CLI)
```bash
# Create a GH secret for repository (replace values)
gh secret set RUNNER_MGMT_TOKEN --body "$RUNNER_MGMT_TOKEN" --repo kushin77/self-hosted-runner
gh secret set DEPLOY_SSH_KEY --body "$DEPLOY_SSH_KEY" --repo kushin77/self-hosted-runner

# Example for GCP DR keys
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$(cat service-account.json)" --repo kushin77/self-hosted-runner
gh secret set GCP_PROJECT_ID --body "my-gcp-project" --repo kushin77/self-hosted-runner
```

Security and rotation best practices
- Rotate automation tokens every 30 days (or earlier). Record rotation events in `docs/SECRETS_ROTATION.md`.
- Use short-lived credentials or ephemeral tokens where possible.
- Restrict token scope and IP access if supported by platform.
- Audit repository secret access and usage logs periodically.

Verification after provisioning
1. Confirm secrets appear in repository Settings → Secrets & variables → Actions.
2. Trigger a controlled workflow run that requires the secrets (e.g., `runner-self-heal` or DR test) in a staging environment.
3. Validate logs and artifacts for successful access and cleanup.

If you want me to create rotation docs and automation PRs for secret rotation, reply `create-rotation-docs` in the issue and I will open a follow-up PR.

— Automation Team
