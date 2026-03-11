Provisioning GITHUB_TOKEN into Google Secret Manager (GSM)

Purpose
- Provide a secure, idempotent way to place a GitHub token into GSM so the orchestrator
  can fetch it via `scripts/secrets/fetch-secret-oidc-gsm-vault.sh` and `run-with-secret.sh`.

Files
- `scripts/secrets/provision-github-token-to-gsm.sh` — idempotent helper to create the secret and add a version.

Quick example (local, one-time):

```bash
export GCP_PROJECT=my-gcp-project
export GITHUB_TOKEN_VALUE="ghp_..."   # set in your shell securely (do not commit)
# Create or add the token as a secret named 'github-token'
./scripts/secrets/provision-github-token-to-gsm.sh github-token
```

Automation / CI
- For CI, use a secure operator identity to call the script (avoid exposing `GITHUB_TOKEN_VALUE` in logs).
- Grant the operator SA the role `roles/secretmanager.secretAccessor` for read access at runtime.

Example IAM binding (one-time, run by owner):

```bash
gcloud secrets add-iam-policy-binding github-token --project=$GCP_PROJECT \
  --member='serviceAccount:ORCHESTRATOR_SA@${GCP_PROJECT}.iam.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'
```

Security notes
- Do NOT commit `GITHUB_TOKEN_VALUE` to git or logs.
- The provisioning script avoids printing the token and writes secret material only to GSM.
- Rotate the token periodically and update the secret by re-running the script (it adds a new version).

Next steps
- After provisioning, set `GITHUB_TOKEN_SECRET_NAME=github-token` and `GSM_PROJECT` (or `GCP_PROJECT`) in the orchestrator's environment or CI configuration so the orchestrator can fetch the token via the secret helper.
