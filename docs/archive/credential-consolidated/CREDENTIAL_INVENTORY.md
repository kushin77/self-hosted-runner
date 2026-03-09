# 🔐 Credential Inventory & Migration Plan

**Date:** March 8, 2026  
**Status:** Phase 1A - Inventory Complete  
**Phase Required:** IMMEDIATE (blocking all Phase 2-5)

---

## CRITICAL REQUIREMENT: ZERO HARDCODING

All credentials must be:
- ✅ Rotated automatically (daily/weekly/monthly)
- ✅ Stored externally (GSM/Vault/KMS only)
- ✅ Retrieved at runtime using OIDC/WIF
- ✅ Logged immutably in audit trail
- ✅ Destroyed after TTL expires

---

## 📊 CURRENT STATE: 25 Secrets in GitHub Repository Settings

### AWS Credentials (4/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `AWS_ACCESS_KEY_ID` | ~1 day ago | Access Key | ⚠️ LONG-LIVED |
| `AWS_SECRET_ACCESS_KEY` | ~1 day ago | Access Key | ⚠️ LONG-LIVED |
| `AWS_ROLE_TO_ASSUME` | ~19 hours ago | IAM Role ARN | ✅ Non-secret |
| `AWS_KMS_KEY_ID` | ~6 hours ago | KMS Key ID | ✅ Non-secret |

**Action:** Migrate to AWS Secrets Manager > KMS for rotation  
**Migration Strategy:** OIDC role-based (no long-lived keys)

### GCP/GSM Credentials (5/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `GCP_PROJECT_ID` | ~6 hours ago | Project ID | ✅ Non-secret |
| `GCP_SERVICE_ACCOUNT_EMAIL` | ~8 hours ago | Service Account | ✅ Non-secret |
| `GCP_SERVICE_ACCOUNT_KEY` | ~17 hours ago | Service Account Key | ⚠️ NEEDS ROTATION |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | ~2 hours ago | WIF Provider | ✅ Non-secret |
| `GOOGLE_CREDENTIALS` | ~20 hours ago | JSON Credentials | ⚠️ LONG-LIVED |

**Action:** Migrate to Google Secret Manager (Primary)  
**Migration Strategy:** WIF-based OIDC (eliminate service account keys)

### Vault Credentials (4/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `VAULT_ADDR` | ~6 hours ago | Server URL | ✅ Non-secret |
| `VAULT_NAMESPACE` | ~2 days ago | Namespace | ✅ Non-secret |
| `VAULT_ROLE_ID` | ~2 days ago | AppRole ID | ⚠️ NEEDS ROTATION |
| `VAULT_SECRET_ID` | ~2 days ago | AppRole Secret | ⚠️ HIGH PRIORITY (expires) |

**Action:** Migrate to Vault (Secondary - Dynamic tokens)  
**Migration Strategy:** JWT-based authentication (eliminate AppRole secrets)

### Docker/Container Registry Credentials (4/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `DOCKER_HUB_USERNAME` | ~1 day ago | Username | ⚠️ NEEDS ROTATION |
| `DOCKER_HUB_PASSWORD` | ~1 day ago | Password | ⚠️ NEEDS ROTATION |
| `GHCR_TOKEN` | ~1 day ago | Personal Access Token | ⚠️ NEEDS ROTATION |
| `REGISTRY_USERNAME` | ~1 day ago | Username | ⚠️ NEEDS ROTATION |

**Action:** Migrate to GSM (Docker credentials via WIF)  
**Migration Strategy:** Use Docker CLI with GSM credentials, OIDC for GHCR

### SSH & Deployment Credentials (2/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `DEPLOY_SSH_KEY` | ~17 hours ago | SSH Private Key | ⚠️ EPHEMERAL NEEDED |
| `RUNNER_MGMT_TOKEN` | ~1 day ago | GitHub Token | ⚠️ HIGH PRIORITY |

**Action:** Migrate to Vault (ephemeral + rotation)  
**Migration Strategy:** Vault generates temporary SSH certs + GitHub PAT rotation

### Infrastructure Secrets (2/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `MINIO_BUCKET` | ~1 day ago | S3 Bucket Name | ✅ Non-secret |
| `TFSTATE_BUCKET` | ~20 hours ago | S3 Bucket Name | ✅ Non-secret |

**Action:** Already non-secrets (just names)  
**Status:** ✅ COMPLIANT

### Code Signing & Webhooks (3/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `COSIGN_KEY` | ~1 day ago | Private Key (Cosign) | ⚠️ NEEDS ROTATION |
| `SLACK_WEBHOOK_URL` | ~1 day ago | Webhook URL | ⚠️ NEEDS ROTATION |
| `PROD_TFVARS` | ~20 hours ago | Terraform Vars | ⚠️ MAY CONTAIN SECRETS |

**Action:** Migrate to GSM (keys + webhooks)  
**Migration Strategy:** WIF for signing, rotate webhook URLs monthly

### Terraform Variables (1/25)
| Secret | Updated | Type | Status |
|--------|---------|------|--------|
| `TF_VAR_SERVICE_ACCOUNT_KEY` | ~2 days ago | JSON Key | ⚠️ LONG-LIVED |

**Action:** Migrate to Vault  
**Migration Strategy:** Use Vault provider in Terraform (dynamic credentials)

---

## 🎯 MIGRATION PRIORITIES

### TIER 1: IMMEDIATE (This Week)
**10 secrets must move by EOW**
- 🔴 `VAULT_SECRET_ID` (AppRole Secret - expires!)
- 🔴 `RUNNER_MGMT_TOKEN` (GitHub Token)
- 🔴 `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
- 🔴 `GCP_SERVICE_ACCOUNT_KEY` + `GOOGLE_CREDENTIALS`
- 🔴 `DOCKER_HUB_PASSWORD` + `GHCR_TOKEN`
- 🔴 `DEPLOY_SSH_KEY`
- 🔴 `COSIGN_KEY`

**Timeline:** 3 days (Tue-Thu)  
**Blocker:** Without these, no workflows can run in Phase 2+

### TIER 2: HIGH PRIORITY (Week 2)
**8 secrets with medium urgency**
- 🟠 `DOCKER_HUB_USERNAME` (username-only exposure)
- 🟠 `REGISTRY_USERNAME` (username-only exposure)
- 🟠 `VAULT_ROLE_ID` (should rotate periodically)
- 🟠 `SLACK_WEBHOOK_URL` (can be cycled monthly)
- 🟠 `PROD_TFVARS` (if contains secrets)
- 🟠 `TF_VAR_SERVICE_ACCOUNT_KEY`
- 🟠 `GCP_SERVICE_ACCOUNT_EMAIL` (if sensitive)
- 🟠 `AWS_KMS_KEY_ID` (if sensitive)

**Timeline:** 5 days (following week)

### TIER 3: NICE-TO-HAVE (Week 3)
**7 non-secret values (reference only)**
- 🟡 `AWS_ROLE_TO_ASSUME` (ARN - non-sensitive)
- 🟡 `GCP_PROJECT_ID` (Project ID - public)
- 🟡 `GCP_WORKLOAD_IDENTITY_PROVIDER` (WIF URI - non-sensitive)
- 🟡 `VAULT_ADDR` (Server URL - non-sensitive)
- 🟡 `VAULT_NAMESPACE` (Namespace - non-sensitive)
- 🟡 `MINIO_BUCKET` (Bucket name - non-sensitive)
- 🟡 `TFSTATE_BUCKET` (Bucket name - non-sensitive)

**Note:** These can remain as GitHub secrets or be moved to .gitignore'd environment variables

---

## 📋 MIGRATION MATRIX

### Where Each Secret Goes:

| GitHub Secret | Target System | Rotation | Retrieval Method | TTL |
|---------------|---------------|----------|------------------|-----|
| `AWS_ACCESS_KEY_ID` | AWS Secrets Manager | Daily | OIDC role | 24h |
| `AWS_SECRET_ACCESS_KEY` | AWS Secrets Manager | Daily | OIDC role | 24h |
| `AWS_ROLE_TO_ASSUME` | Repo ENV or file | N/A | Direct | ∞ |
| `AWS_KMS_KEY_ID` | Repo ENV or file | N/A | Direct | ∞ |
| `GCP_PROJECT_ID` | Repo ENV or file | N/A | Direct | ∞ |
| `GCP_SERVICE_ACCOUNT_EMAIL` | Repo ENV or file | N/A | Direct | ∞ |
| `GCP_SERVICE_ACCOUNT_KEY` | Google Secret Manager | Weekly | WIF (OIDC) | 7d |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Repo ENV or file | N/A | Direct | ∞ |
| `GOOGLE_CREDENTIALS` | Google Secret Manager | Weekly | WIF (OIDC) | 7d |
| `VAULT_ADDR` | Repo ENV or file | N/A | Direct | ∞ |
| `VAULT_NAMESPACE` | Repo ENV or file | N/A | Direct | ∞ |
| `VAULT_ROLE_ID` | Vault AppRole (managed) | Weekly | JWT auth | 7d |
| `VAULT_SECRET_ID` | Vault AppRole (managed) | Daily | JWT auth | 24h |
| `DOCKER_HUB_USERNAME` | Google Secret Manager | Monthly | GSM retrieval | 30d |
| `DOCKER_HUB_PASSWORD` | Google Secret Manager | Monthly | GSM retrieval | 30d |
| `GHCR_TOKEN` | Google Secret Manager | Monthly | GSM retrieval | 30d |
| `REGISTRY_USERNAME` | Google Secret Manager | Monthly | GSM retrieval | 30d |
| `DEPLOY_SSH_KEY` | Vault (dynamic certs) | Daily | Vault SSH engine | 24h |
| `RUNNER_MGMT_TOKEN` | Vault (GitHub token source) | Weekly | JWT auth | 7d |
| `SLACK_WEBHOOK_URL` | Google Secret Manager | Monthly | GSM retrieval | 30d |
| `COSIGN_KEY` | Google Secret Manager | Weekly | GSM retrieval | 7d |
| `PROD_TFVARS` | Google Secret Manager (if secrets) | As-needed | GSM retrieval | 30d |
| `TF_VAR_SERVICE_ACCOUNT_KEY` | Vault + Terraform provider | Dynamic | Vault provider | 1h |
| `MINIO_BUCKET` | `.env.local` or .gitignore'd | N/A | Direct | ∞ |
| `TFSTATE_BUCKET` | `.env.local` or .gitignore'd | N/A | Direct | ∞ |

---

## 🛠️ IMPLEMENTATION PLAN

### Phase 1A-1: GSM Setup (Day 1 - Tuesday)
1. Enable Google Secret Manager API
2. Create service account with GSM admin role
3. Setup WIF provider in GCP
4. Create initial secrets in GSM:
   - `docker-hub-username`
   - `docker-hub-password`
   - `ghcr-token`
   - `registry-username`
   - `slack-webhook-url`
   - `cosign-key`
   - `gcp-service-account-key`
   - `google-credentials`

### Phase 1A-2: Vault Setup (Day 2 - Wednesday)
1. Ensure Vault server is running
2. Enable JWT auth method
3. Create GitHub Actions JWT role
4. Configure AppRole for initial setup
5. Create secrets in Vault:
   - `github-pat-core`
   - `deploy-ssh-key`
   - `runner-mgmt-token`
   - `tf-service-account-key`

### Phase 1A-3: KMS Setup (Day 2 - Wednesday)
1. Ensure AWS KMS key exists
2. Create IAM policy for key access
3. Test OIDC role assumption

### Phase 1A-4: Helper Actions (Day 3 - Thursday)
1. Update `.github/actions/retrieve-secret-gsm/action.yml`
2. Update `.github/actions/retrieve-secret-vault/action.yml`
3. Create `.github/actions/retrieve-secret-kms/action.yml`
4. Test all three helper actions

### Phase 1A-5: Rotation Workflows (Day 4 - Friday)
1. Deploy `gcp-gsm-rotation.yml` (daily, 3 AM UTC)
2. Deploy `vault-secret-rotation.yml` (weekly, Sun 1 AM UTC)
3. Deploy `aws-kms-rotation.yml` (monthly, 1st 2 AM UTC)
4. Test rotation in staging

### Phase 1A-6: Compliance & Audit (Day 5 - Friday)
1. Initialize `.audit-trail/credential-operations.log`
2. Deploy `credential-audit-compliance.yml`
3. Validate zero-hardcoding with security scan
4. Close #1966 with sign-off

---

## ✅ ACCEPTANCE CRITERIA

### Infrastructure
- [x] Credential inventory completed (25 GitHub secrets cataloged)
- [ ] GSM created with 8 secrets
- [ ] Vault configured with 4 secrets
- [ ] AWS KMS accessible via OIDC
- [ ] OIDC/WIF providers configured (GCP + AWS)

### Helper Actions
- [ ] `retrieve-secret-gsm` working
- [ ] `retrieve-secret-vault` working
- [ ] `retrieve-secret-kms` working
- [ ] All tested with at least 1 test workflow

### Rotation Workflows
- [ ] GSM rotation deployed (daily)
- [ ] Vault rotation deployed (weekly)
- [ ] KMS rotation deployed (monthly)
- [ ] Each tested in staging

### Migration
- [ ] All 25 GitHub secrets migrated or marked N/A
- [ ] No long-lived AWS/GCP service account keys in GitHub
- [ ] All workflows use helper actions (not direct secrets)
- [ ] Zero hardcoded credentials in repo

### Audit & Compliance
- [ ] Immutable audit trail created
- [ ] Compliance report shows 100% external credential management
- [ ] Team trained on new workflow
- [ ] Security scan shows zero credential files

---

## 📌 BLOCKERS

- [ ] GSM infrastructure (GCP project setup)
- [ ] Vault server (admin setup required)
- [ ] OIDC providers (admin configuration)
- [ ] AWS IAM role (admin creation)
- [ ] GitHub repo admin access (to update secrets)

---

## 🎯 SUCCESS METRICS

| Metric | Target | Current |
|--------|--------|---------|
| Hardcoded secrets in repo | 0 | 25 |
| Secrets using OIDC retrieval | 100% | 0% |
| Automatic rotation coverage | 100% | 0% |
| Audit trail completeness | 100% | 0% |
| Mean time to rotate secret | <5 min automated | N/A |
| Secret breach recovery time | <10 min | N/A |

---

## 📞 NEXT STEPS

**Immediate (Next 2 hours):**
1. Review this inventory ✅
2. Get admin access to GCP, Vault, AWS
3. Confirm GSM + Vault infrastructure available
4. Create admin checklist from "BLOCKERS" section

**This Week (Tue-Fri):**
1. Execute GSM setup
2. Execute Vault setup
3. Execute KMS setup
4. Deploy helper actions
5. Deploy rotation workflows
6. Validate zero-hardcoding

**Next Week:**
1. Train team on credential workflow
2. Monitor rotation workflows
3. Close Phase 1A issue

---

**CRITICAL:** Phase 2-5 cannot start until this is complete. All workflows require external credential management.

Reference: [Issue #1966](../../../issues/1966)
