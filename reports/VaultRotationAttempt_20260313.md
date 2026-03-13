# Vault Rotation Attempt — 2026-03-13

Summary:
- Attempted to run `scripts/secrets/run_vault_rotation.sh` using GSM secrets in project `nexusshield-prod`.
- Result: Vault unreachable (DNS resolution failure for `vault.internal`). Vault rotation was skipped/failed.

Log (stdout/stderr):

```
Starting Vault AppRole rotation at Fri Mar 13 12:56:45 AM UTC 2026
Checking Vault health at https://vault.internal
curl: (6) Could not resolve host: vault.internal
ERROR: cannot contact Vault at https://vault.internal with provided token
```

Next steps:
- Provide a reachable `VAULT_ADDR` (HTTPS) and ensure network access from Cloud Build and runners.
- Ensure `VAULT_TOKEN` (or AppRole role_id/secret_id) is available in GSM and accessible by the Build SA.
- After operator provides values, re-run the Cloud Build: `gcloud builds submit --config=cloudbuild/run-vault-rotation.yaml --substitutions=_GSM_PROJECT=nexusshield-prod`.

