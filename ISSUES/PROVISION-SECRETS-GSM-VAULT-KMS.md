Title: Provision production secrets into Google Secret Manager + HashiCorp Vault + AWS KMS (break-glass)

Description
- The deployment framework requires the following secrets to be present and accessible by the deployer service account (SA):
  - `portal-db-password` (Secret Manager path: `projects/<PROJECT>/secrets/portal-db-password`)
  - `portal-api-key` (Secret Manager path: `projects/<PROJECT>/secrets/portal-api-key`)
  - `gcp-service-account-key` (if using keyfile fallback)

Required actions
- Create secrets in Google Secret Manager with at least one enabled `latest` version.
- Replicate/backup secrets into HashiCorp Vault (path and policies to be provided) for secondary fallback.
- Ensure AWS KMS-encrypted environment variable or object is available as tertiary fallback for emergency.
- Grant the deployer SA the `roles/secretmanager.secretAccessor` role on the secrets.

Verification steps
- Run `infra/credentials/validate-credentials.sh` from repo root and confirm all checks pass.
- Confirm Cloud Run revision can mount `portal-db-password` and start.

Notes
- If you need the exact deployer SA name, see `nexusshield/infrastructure/terraform/production/outputs.tf` or open an audit request.
- Contact: infra-team (cc:network-security)
