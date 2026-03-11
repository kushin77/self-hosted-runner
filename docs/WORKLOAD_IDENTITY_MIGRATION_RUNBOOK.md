# Workload Identity Migration Runbook

Generated: 2026-03-11

Purpose
-------
Provide an idempotent, auditable, and reversible plan to migrate the runner and workloads away from long-lived service account keys to Workload Identity / keyless authentication. This runbook is written to support the project's governance constraints: immutable audit trail, ephemeral credentials, GSM/Vault/KMS canonical secrets, idempotent operations, and hands-off automation.

Scope
-----
- Migrate the operator/runner (`nxs-automation-sa`) and related operator service accounts to use Workload Identity Federation or Workload Identity (depending on workload type).
- Update Cloud Run, Cloud Functions, Cloud Scheduler, and automation scripts to stop relying on SA key files and instead use either:
  - Workload Identity Federation (external CI/workers), or
  - Native service-account assignment with no keys for Google-managed runtimes.

Assumptions
-----------
- You have Org/Project Owner or IAM privileges to create Workload Identity Pools and Providers and to bind IAM roles.
- `gcloud` and `jq` are available on the runner used for automation.
- All key material is stored in GSM or Vault; no secret keys remain in source control.

High-level Plan (phases)
------------------------
1. Audit & discovery (idempotent): list service accounts, keys, and dependent resources.
2. Prepare GSM: ensure target SA keys are uploaded as backup versions in GSM (for rollback only).
3. Create Workload Identity Pool + Provider for the runner environment (external identity or CI system).
4. Bind pool/principal to target Google Service Account with `roles/iam.workloadIdentityUser`.
5. Update automation to acquire tokens from the pool provider (OIDC) and exchange for Google credentials.
6. Migrate Cloud Run / Cloud Functions / Scheduler examples to use keyless service accounts (where applicable).
7. Remove long-lived keys from service accounts (idempotent delete); if a key is system-managed, document and accept.
8. Verification and monitoring: run smoke checks, append audit events, and close migration issue.

Commands & Examples
-------------------
Note: Replace placeholders in angled brackets.

1) Discovery (safe to run repeatedly)

```bash
# list SAs and keys
gcloud iam service-accounts list --project=nexusshield-prod --format='table(email)'
gcloud iam service-accounts keys list --iam-account=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com --project=nexusshield-prod --format=json

# enumerate workloads
gcloud run services list --project=nexusshield-prod --platform=managed --region=us-central1 --format=json > artifacts/discovery/run-services.json
gcloud functions list --project=nexusshield-prod --format=json > artifacts/discovery/functions.json
gcloud scheduler jobs list --project=nexusshield-prod --location=us-central1 --format=json > artifacts/discovery/scheduler.json
```

2) Create Workload Identity Pool + Provider (example for GitHub Actions / external OIDC)

```bash
POOL_ID=my-pool
PROVIDER_ID=github-provider
gcloud iam workload-identity-pools create $POOL_ID --project=nexusshield-prod --location="global" --display-name="Runner federation pool" --description="Pool for self-hosted runner federation"

gcloud iam workload-identity-pools providers create-oidc $PROVIDER_ID \
  --project=nexusshield-prod --location="global" --workload-identity-pool=$POOL_ID \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --allowed-audiences="https://github.com/<org>/<repo>" \
  --display-name="GitHub Actions OIDC provider"

# Validate provider
gcloud iam workload-identity-pools providers describe $PROVIDER_ID --workload-identity-pool=$POOL_ID --project=nexusshield-prod --location=global
```

3) Grant Workload Identity User to the Service Account

```bash
# This binds principals from the pool to impersonate the SA
gcloud iam service-accounts add-iam-policy-binding nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com \
  --project=nexusshield-prod \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.BASE64_BLOB_REDACTED$POOL_ID/attribute.repository/<org>/<repo>"
```

4) Update Runner / Automation to use the provider (example: use `gcloud` with token exchange)

High-level: request an OIDC token from the identity provider, then exchange for a Google access token. Implement on the runner side using short-lived tokens and the google-auth libraries.

5) Migrate Cloud Run / Cloud Function usage (if any rely on key files)

For Cloud Run services hosted in GCP, prefer assigning a service account directly:

```bash
gcloud run services update <service> --service-account=<service-account-email> --region=us-central1 --project=nexusshield-prod
```

6) Revoke old keys (idempotent)

```bash
# list keys and delete user-managed ones (skip system-managed)
gcloud iam service-accounts keys list --iam-account=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com --project=nexusshield-prod --format='value(name)' | while read -r k; do
  echo "consider deleting $k";
  # to delete (do after verification):
  # gcloud iam service-accounts keys delete "$k" --iam-account=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com --quiet || echo "failed:$k"
done
```

Verification
------------
- Use `gcloud auth print-identity-token` and `gcloud auth print-access-token` flows to confirm token exchange works.
- Run automated smoke checks: `scripts/verify/smoke_check.sh` and `infra/terraform/tmp_observability/verify_deploy.sh`.
- Check Cloud Audit Logs for `workloadIdentityPools` usage and absence of key-based auth events.

Rollback
--------
- If migration fails, re-enable temporary SA key usage by adding the key back to `GOOGLE_APPLICATION_CREDENTIALS` from GSM (backup versions kept), then retry migration after fixes. All actions must be appended to `logs/deploy-blocker/*.jsonl`.

Governance & Audit
------------------
- Every significant action must append a JSONL record to `logs/deploy-blocker/` and be committed to `artifacts/audit/` (force-add if ignored) to preserve an immutable trace.
- Use feature flags in automation scripts: `ALLOW_KEY_AUTH=0` by default, `ALLOW_WIF=1` to gate rollout.

Appendix: Useful commands
-------------------------
- Describe pool and providers: `gcloud iam workload-identity-pools describe --location=global --project=...` and `gcloud iam workload-identity-pools providers describe ...`
- Grant impersonation: `gcloud iam service-accounts add-iam-policy-binding` with `roles/iam.workloadIdentityUser` (idempotent).

Contact
-------
Create comments on issue #2521 for coordination and link to this runbook.

-- End runbook
