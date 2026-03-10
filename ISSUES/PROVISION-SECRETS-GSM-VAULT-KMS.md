Title: Provision production secrets into Google Secret Manager + HashiCorp Vault + AWS KMS (break-glass)

Description
- The deployment framework requires the following secrets to be present and accessible by the deployer service account (SA):
  - `portal-db-password` (Secret Manager path: `projects/<PROJECT>/secrets/portal-db-password`)
  - `portal-api-key` (Secret Manager path: `projects/<PROJECT>/secrets/portal-api-key`)
  - `gcp-service-account-key` (if using keyfile fallback)

Required actions (urgent)
- Priority: **High** — Cloud Run cannot start until DB secret version exists.
- Assignee: `infra-team` (or `security-ops` to provision Vault replication)
- Steps:
  1. Create the secrets in GSM (example commands):

    gcloud secrets create nexusshield-portal-db-connection-production --project=<PROJECT> --replication-policy="automatic"
    echo -n "postgresql://user:password@<DB_HOST>:5432/nexusshield_portal?sslmode=require" | gcloud secrets versions add nexusshield-portal-db-connection-production --data-file=- --project=<PROJECT>

  2. Grant the portal service account access:

    gcloud secrets add-iam-policy-binding nexusshield-portal-db-connection-production --member="serviceAccount:nxs-portal-production@<PROJECT>.iam.gserviceaccount.com" --role="roles/secretmanager.secretAccessor" --project=<PROJECT>

  3. (Optional) Replicate into Vault and configure AWS KMS tertiary fallback as per `infra/credentials/CREDENTIAL_MANAGEMENT_FRAMEWORK.md`.

Verification steps
- Run `infra/credentials/validate-credentials.sh` from repo root and confirm all checks pass.
- Confirm Cloud Run revision can mount `portal-db-password` and start.

Notes
- If you need the exact deployer SA name, see `nexusshield/infrastructure/terraform/production/outputs.tf` or open an audit request.
- Contact: infra-team (cc:network-security)
