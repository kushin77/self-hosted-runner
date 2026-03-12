Runner Workload Identity (OIDC) Integration

Purpose
- Provide an idempotent, minimal helper for configuring self-hosted runners to leverage GCP Workload Identity Federation.
- No service account keys are used; tokens are short-lived and ephemeral.

Prerequisites
- Workload Identity Pool and Provider exist (runner-pool-20260311 / runner-provider-20260311)
- Service account created and bound (runner-oidc@nexusshield-prod.iam.gserviceaccount.com)
- Network connectivity from runner to Google IAM STS and GCP endpoints

Usage
1. On the runner host, copy `infra/runner-oidc-deploy.sh` and run as root:

```bash
sudo bash infra/runner-oidc-deploy.sh
```

2. This writes `/etc/nexusshield/runner/oidc-config.env` with these env vars:
- `GCP_PROJECT`
- `WORKLOAD_IDENTITY_PROVIDER`
- `SERVICE_ACCOUNT`

3. Implement the platform-specific OIDC token fetch (self-hosted runner must supply OIDC token/assertion to exchange).
   - The runner then exchanges the OIDC token for a GCP access token scoped to `SERVICE_ACCOUNT` using IAM STS.

Security Notes
- File permissions set to `600` and owned by `root`.
- No keys or long-lived credentials are written.
- The flow is idempotent and safe to re-run.

Troubleshooting
- Verify `gcloud iam workload-identity-pools providers describe runner-provider-20260311 ...` returns expected attribute mapping.
- Check Cloud Audit Logs for token exchange events.

