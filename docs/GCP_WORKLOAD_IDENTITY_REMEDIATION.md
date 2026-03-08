# GCP Workload Identity Fix — Remediation Guide

## Overview

The Vault + KMS credential rotation workflows are failing at the **GCP Secret Manager reconciliation** step with:

```
ERROR: Unable to acquire impersonated credentials
Not found; Gaia id not found for email ***
```

This indicates **Workload Identity Federation (WIF) mapping misconfiguration**.

## Root Cause

When using `google-github-actions/auth@v2`, the three required components are:

1. **WIF Provider exists** in the GCP project  
2. **Service account exists** in the project  
3. **IAM binding** `roles/iam.serviceAccountTokenCreator` exists on the service account  

If any are missing, gcloud fails with a 404 error.

## Repository Secrets Required

All of these must be set:

- `GCP_PROJECT_ID` = GCP project ID (e.g., `gcp-eiq`)  
- `GCP_SERVICE_ACCOUNT_EMAIL` = Service account email (e.g., `terraform-runner@gcp-eiq.iam.gserviceaccount.com`)  
- `GCP_WORKLOAD_IDENTITY_PROVIDER` = WIF provider resource name (e.g., `projects/123456/locations/global/workloadIdentityPools/github-pool/providers/github-provider`)  

## Automated Remediation

Dispatch the remediation workflow to validate and fix automatically:

```bash
# Dry-run (validate only)
gh workflow run gcp-workload-identity-remediation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main

# Auto-remediate (apply fixes)
gh workflow run gcp-workload-identity-remediation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f auto_remediate=true \
  -f dry_run=false
```

## Validation

After remediation, run the validator:

```bash
gh workflow run gcp-auth-validate.yml --repo kushin77/self-hosted-runner --ref main
```

Look for:
- ✓ `gcloud auth list` shows authenticated account
- ✓ `gcloud auth print-identity-token` returns a token
- ✓ `gcloud secrets list` lists GSM secrets without 404 errors

## Re-run Rotation

Once validation passes:

```bash
gh workflow run vault-kms-credential-rotation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f rotation_mode=full
```

---

**Last Updated:** March 8, 2026
