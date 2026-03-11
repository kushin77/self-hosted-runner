# Credential Management & GCP Secret Manager Integration

**Last Updated:** 2026-03-11T00:53:47Z  
**Status:** Production  
**Compliance:** GSM/KMS mandatory for all credentials

## Overview

All sensitive credentials are now managed exclusively through **Google Cloud Secret Manager (GSM)** with automatic KMS encryption. No credentials are stored in Git, environment files, or deployment manifests.

## Credential Architecture

| Service          | Secret Name                | Purpose                     | Owner              |
|------------------|-----------------------------|-----------------------------|--------------------|
| Backend Service  | `backend-db-secret`         | PostgreSQL authentication   | Platform Team       |
| Backend Service  | `backend-auth-secret`       | Auth token signing          | Security Team       |
| Image Pin        | `image-pin-authn`           | API authentication          | Platform Team       |
| Deployment       | `github-deploy-authn`       | Git repository access       | DevOps Team         |
| Deployment       | `gcp-cloud-run-authn`       | GCP service auth            | DevOps Team         |

## Implementation Steps

### Step 1: Initialize GSM Infrastructure

```bash
# Use automated setup script (recommended)
bash scripts/init-gsm-credentials.sh
```

This script:
- Creates Secret Manager secrets for all services
- Configures IAM access policies for service accounts
- Validates KMS encryption configuration
- Performs credential access audit

### Step 2: Populate Secrets

```bash
# Example: Add database credential
gcloud secrets versions add backend-db-secret \
  --data-file=- \
  --project=nexusshield-prod < /path/to/secure/creds

# Example: Add auth secret
gcloud secrets versions add backend-auth-secret \
  --data-file=- \
  --project=nexusshield-prod < /path/to/secure/creds
```

**Important:** Source credentials from secure location only (not from email, SMS, or unencrypted messages).

### Step 3: Grant Service Account Access

Done automatically by init script. Verify:

```bash
gcloud secrets get-iam-policy backend-db-secret --project=nexusshield-prod
```

Should show your Cloud Run service account has `roles/secretmanager.secretAccessor`.

### Step 4: Update Services to Fetch Secrets

**Implementation (canonical source)**

Do not copy these examples into implementations to avoid stale docs. Refer to the canonical runtime helpers in the repository:

- Backend GSM helper: [backend/server.js](backend/server.js)
- Shared utilities: [backend/lib/utils.js](backend/lib/utils.js)

These helpers use the Google Cloud Secret Manager client and are the single source of truth for secret access patterns in the codebase.

## Security Guarantees

✅ **At-Rest Encryption:** Google-managed or customer-managed KMS keys  
✅ **Access Control:** IAM-based, immutable per service  
✅ **Audit Logging:** All access logged for 90 days  
✅ **No Disk Exposure:** Secrets fetched at runtime, never persisted  
✅ **No Git History:** Purged via destructive rewrite (see SECURITY_REMOVALS.md)  
✅ **Automatic Rotation:** Framework supports 0-downtime secret updates  

## Terraform Module

Automated provisioning via Terraform:

```bash
cd terraform/gsm_credentials
terraform init
terraform plan
terraform apply -var="project_id=nexusshield-prod"
```

This creates all secrets with proper IAM bindings.

## Audit & Monitoring

Query recent secret access:

```bash
gcloud logging read \
  'protoPayload.methodName=google.cloud.secretmanager.v1.SecretManagerService.AccessSecretVersion' \
  --freshness 24h \
  --project=nexusshield-prod \
  --limit 50 \
  --format=json
```

24-hour monitoring alert configured in `monitoring/production_24h_health_policy.json` detects anomalous access patterns.

## Compliance Checklist

- [ ] All secrets created in Secret Manager
- [ ] All secret versions populated with actual values
- [ ] Service accounts granted secretAccessor IAM role
- [ ] Services updated to fetch secrets (not env vars)
- [ ] Terraform module applied to infrastructure
- [ ] Audit logs configured for 90-day retention
- [ ] Quarterly credential rotation schedule established
- [ ] 24-hour monitoring alert enabled

## Credential Rotation

Rotate secrets without service downtime:

```bash
# Add new version
echo -n "$NEW_SECRET_VALUE" | \
  gcloud secrets versions add backend-db-secret \
  --data-file=- --project=nexusshield-prod

# Service automatically uses latest version
# Old versions retained for rollback
```

## Emergency Access

If manual retrieval needed (requires IAM role: `roles/secretmanager.secretAccessor`):

```bash
gcloud secrets versions access latest --secret=backend-db-secret --project=nexusshield-prod
```

## References

- [GCP Secret Manager Docs](https://cloud.google.com/secret-manager/docs)
- [Cloud Run with Secrets](https://cloud.google.com/run/docs/configuring/secrets)
- [Terraform Secret Manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret)
- [OWASP Secrets Management](https://owasp.org/www-community/Sensitive_Data_Exposure)
