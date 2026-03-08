# GCP Workload Identity Fix — Remediation Guide & Automation

## Overview

The Vault + KMS credential rota workflows are failing at the **GCP Secret Manager (GSM) reconciliation** step with the error:

```
ERROR: (gcloud.secrets.list) There was a problem refreshing your current auth tokens: 
('Unable to acquire impersonated credentials', '{"error": {"code": 404, "message": "Not found; 
Gaia id not found for email ***", "status": "NOT_FOUND"}}')
```

This indicates a **Workload Identity Federation (WIF) mapping misconfiguration** — the GitHub Actions OIDC token is not correctly mapping to the GCP service account.

## Root Cause

When using `google-github-actions/auth@v2` with:
- `workload_identity_provider`: The WIF provider resource name
- `service_account`: The service account email

The workflow must:
1. **Have the WIF provider registered** in the GCP project
2. **Have the service account exist** in the project
3. **Have the IAM binding** `roles/iam.serviceAccountTokenCreator` on the service account, allowing the WIF principal to impersonate it

**If any of these are missing**, gcloud fails to acquire the identity token.

## Required Repository Secrets

Ensure these are set in GitHub repo secrets:

| Secret | Example | Purpose |
|--------|---------|---------|
| `GCP_PROJECT_ID` | `gcp-eiq` | GCP project ID |
| `GCP_SERVICE_ACCOUNT_EMAIL` | `terraform-runner@gcp-eiq.iam.gserviceaccount.com` | Service account to impersonate |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/123456/locations/global/workloadIdentityPools/github-pool/providers/github-provider` | WIF provider resource name |

## Remediation Steps

### Option A: Automated Remediation (Recommended)

Dispatch the remediation workflow to validate and auto-fix:

```bash
gh workflow run gcp-workload-identity-remediation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f auto_remediate=true \
  -f dry_run=false
```

**Dry-run mode** (no changes):

```bash
gh workflow run gcp-workload-identity-remediation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f auto_remediate=false \
  -f dry_run=true
```

### Option B: Manual Remediation via gcloud

If you have GCP admin access:

```bash
# 1. Verify service account exists
gcloud iam service-accounts describe \
  terraform-runner@gcp-eiq.iam.gserviceaccount.com \
  --project=gcp-eiq

# 2. Verify WIF provider exists (parse the provider resource name)
gcloud iam workload-identity-pools providers describe github-provider \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=gcp-eiq

# 3. Add IAM binding (idempotent)
gcloud iam service-accounts add-iam-policy-binding \
  terraform-runner@gcp-eiq.iam.gserviceaccount.com \
  --project=gcp-eiq \
  --role=roles/iam.serviceAccountTokenCreator \
  --member="principalSet://iam.googleapis.com/projects/123456/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
```

## Validation

After remediation, run the validator workflow:

```bash
gh workflow run gcp-auth-validate.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

Check the validator logs for:
- ✓ `gcloud auth list` shows authenticated account
- ✓ `gcloud auth print-identity-token` returns a valid token
- ✓ `gcloud secrets list` lists GSM secrets without 404 errors
- ✓ `gcloud iam service-accounts get-iam-policy` returns the service account policy

## Re-running Rotation After Fix

Once validation passes, dispatch the rotation workflow:

```bash
gh workflow run vault-kms-credential-rotation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f rotation_mode=full
```

## Idempotency & No-ops

All remediation steps are **idempotent**:
- Checking for existing service account is non-destructive
- Checking for existing WIF provider is non-destructive  
- Adding IAM bindings is idempotent (gcloud deduplicates)
- Dry-run mode allows pre-flight validation

## Automation Integration

The remediation can be triggered automatically as part of the rotation workflow chain:

```yaml
- name: Remediate GCP Workload Identity (if needed)
  id: remediate_wif
  run: |
    gh workflow run gcp-workload-identity-remediation.yml \
      --repo "${{ github.repository }}" \
      --ref "${{ github.ref_name }}" \
      -f auto_remediate=true \
      -f dry_run=false
  if: ${{ failure() && contains(github.event.job.steps[*].conclusion, 'Reconcile GSM') }}
```

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| "Not found; Gaia id not found" | WIF provider or binding missing | Run remediation workflow |
| "could not deserialize key data" | Corrupted/unsupported service account key | Check if using `GOOGLE_CREDENTIALS` vs. native WIF |
| "Unknown service account" | Service account doesn't exist in project | Verify `GCP_SERVICE_ACCOUNT_EMAIL` secret; create SA if needed |
| "Permission denied" | Insufficient IAM permissions | Ensure workflow OIDC role has `iam.serviceAccountAdmin` or higher |

## References

- [Google Cloud Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [google-github-actions/auth@v2 Documentation](https://github.com/google-github-actions/auth)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

---

**Last Updated:** March 8, 2026  
**Workflow Status:** Remediation in progress
