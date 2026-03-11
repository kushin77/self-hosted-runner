# Workload Identity Migration Plan

Purpose: migrate runner and automation workloads from long-lived service account keys to Workload Identity (WIF) to eliminate key rotation overhead and improve security.

Goals:
- Remove need for SA JSON keys for runners and CI automation
- Use Google-managed token exchange via Workload Identity Pools and Providers
- Maintain idempotency and reversible steps

High-level steps:
1. Create Workload Identity Pool and Provider (one per external identity domain if needed).
2. Configure IAM bindings: grant `roles/iam.workloadIdentityUser` to provider members for target service accounts (e.g., `nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com`).
3. Update runner configuration to request tokens via WIF (or annotate GKE service account / configure Cloud Run to use `serviceAccount` directly).
4. Deploy configuration changes (Scheduler, Cloud Run, Cloud Build triggers) to use WIF-authenticated identities or direct serviceAccount attachments instead of JSON keys.
5. Verify workloads obtain tokens and can access required APIs.
6. Revoke old service-account keys and remove any secrets from GSM/Vault that are no longer needed.

Idempotency and safety:
- All actions are additive until final key deletion.
- Keep old keys backed up and record all changes in append-only audit logs under `logs/deploy-blocker/` and `artifacts/audit/`.

Prereqs & approvals:
- Organization-level permission to create Workload Identity Pools and bind IAM policy.
- Confirm maintenance windows for any services that cannot be rotated live.

Next actions I can perform if approved:
- Create IaC (Terraform) snippet to provision pool/provider and necessary IAM bindings.
- Update `infra/secrets-orchestrator` Terraform to manage the new resources.
- Roll WIF config to a small pilot workload (e.g., `automation-runner`).

Appendix: Useful gcloud snippets
```bash
# Create pool
gcloud iam workload-identity-pools create wif-pool --project=nexusshield-prod --location="global" --description="Runner WIF pool"

# Create provider
gcloud iam workload-identity-pools providers create-oidc wif-provider \
  --project=nexusshield-prod --location="global" --workload-identity-pool="wif-pool" \
  --issuer-uri="https://accounts.google.com" --attribute-mapping="google.subject=assertion.sub"

# Allow provider to impersonate SA
gcloud iam service-accounts add-iam-policy-binding nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com \
  --project=nexusshield-prod --role roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/wif-pool/attribute.repository/REPO"
```
