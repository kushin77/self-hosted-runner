# Phase 2: Vault JWT AppRole + KMS/GSM Integration
**Date:** 2026-03-09  
**Status:** IN PROGRESS  
**Architecture:** Immutable | Ephemeral | Idempotent | No-Ops | Hands-Off

---

## 🎯 Phase 2 Objectives

### 1. Vault JWT AppRole Authentication
Transform Vault auth from static tokens → ephemeral JWT-based AppRole authentication.

**Implementation:**
- AppRole auth method (role_id + secret_id rotation)
- JWT token signing via OIDC (automatic via GitHub Actions)
- 1-hour token TTL (auto-expire)
- Immutable audit trail (AppRole auth logs)

**Affected Workflows:**
- `phase3-revoke-keys.yml` — Vault credential revocation
- `autonomous-deployment-orchestration.yml` — Infrastructure automation
- `ci-credential-lint.yml` — Credential scanning

### 2. AWS KMS Integration
Enable key rotation + encryption at rest for all AWS credentials stored in GitHub secrets.

**Implementation:**
- KMS master key for credential envelope encryption
- CloudTrail audit logging (immutable)
- Key rotation policy (90-day cycle)
- Lambda function for credential re-encryption

**Scope:**
- Encrypt: GitHub repo secrets → KMS envelope
- Decrypt: Workflow runtime → AppRole + KMS auth
- Audit: CloudTrail + custom JSONL logs

### 3. GCP Secret Manager Integration
Centralize GCP credentials via Secret Manager with rotation policies.

**Implementation:**
- Secret Manager API access (Workload Identity)
- Automatic secret rotation (30-day cycle)
- Version history (immutable)
- IAM access logs

**Scope:**
- Service account keys stored in Secret Manager
- Rotation triggers via Cloud Scheduler
- Version history tracking

---

## 📊 Architecture Diagram

```
GitHub Actions Workflow
    ↓
OIDC Token (auto-issued)
    ├─ GCP: WIF → IAM binding → Workload Identity
    ├─ AWS: STS assume-role → 1h credentials
    │   └─ KMS master key decrypt
    └─ Vault: JWT AppRole → 1h token lease
        └─ AppRole auth logs

Credential Storage (Immutable):
    ├─ GitHub Secrets (encrypted at rest)
    │   └─ Encrypted with KMS master key
    ├─ AWS Secrets Manager (rotated 30d)
    │   └─ KMS master key envelope
    ├─ GCP Secret Manager (rotated 30d)
    │   └─ Version history (immutable)
    └─ Vault (AppRole-authed, 1h TTL)
        └─ Dynamic credentials (auto-revoked)

Audit Trail (Immutable):
    ├─ GitHub Actions logs (JSONL format)
    ├─ CloudTrail (AWS, 365d retention)
    ├─ Cloud Audit Logs (GCP, 14d retention)
    ├─ Vault AppRole auth logs
    └─ Custom JSONL logs in git repo

Auto-Cleanup (Ephemeral):
    ├─ 1h token expiry (all clouds)
    ├─ Automatic credential revocation
    ├─ Stale secret cleanup (90d+)
    └─ Audit log archival → GCS/S3
```

---

## 📋 Implementation Checklist

### Phase 2A: Vault JWT AppRole (Weeks 1-2)

- [ ] Create Vault AppRole auth method
  - [ ] `deployment-automation` role
  - [ ] `credential-rotation` role
  - [ ] `observability` role
  
- [ ] Set up AppRole secret ID rotation
  - [ ] Lambda/Cloud Function for rotation
  - [ ] 7-day secret ID TTL
  - [ ] 30-day lifecycle
  
- [ ] Migrate workflows to JWT auth
  - [ ] Update `phase3-revoke-keys.yml`
  - [ ] Update `autonomous-deployment-orchestration.yml`
  - [ ] Test in staging (manual dispatch)
  
- [ ] Document appRole setup
  - [ ] Role creation steps
  - [ ] Policy templates
  - [ ] Troubleshooting
  
- [ ] Create blocking issues
  - [ ] #2160: Vault Phase 2 planning → IN PROGRESS
  - [ ] #2162: Vault AppRole automation
  - [ ] #2163: AppRole secret rotation

### Phase 2B: AWS KMS Integration (Weeks 3-4)

- [ ] Create KMS master key
  - [ ] 365-day rotation policy
  - [ ] Multi-region replication
  - [ ] CloudTrail audit
  
- [ ] Set up credential envelope encryption
  - [ ] GitHub Secrets → KMS encrypt
  - [ ] Workflow runtime → KMS decrypt
  - [ ] Fallback to plaintext (temporary)
  
- [ ] Enable CloudTrail logging
  - [ ] Enable KMS API logging
  - [ ] 365-day retention
  - [ ] S3 bucket archival
  
- [ ] Create KMS rotation automation
  - [ ] SNS topic for rotation alerts
  - [ ] Lambda for re-encryption
  - [ ] JSONL audit trail
  
- [ ] Create blocking issues
  - [ ] #2164: KMS master key creation + policies
  - [ ] #2165: Credential envelope encryption
  - [ ] #2166: CloudTrail audit setup

### Phase 2C: GCP Secret Manager Integration (Weeks 5-6)

- [ ] Set up Secret Manager API
  - [ ] Enable Secret Manager API
  - [ ] Create service account with Secret Manager admin
  - [ ] Grant Workload Identity permissions
  
- [ ] Migrate stored secrets to Secret Manager
  - [ ] Service account keys
  - [ ] API tokens
  - [ ] OAuth client secrets
  
- [ ] Enable automatic rotation
  - [ ] Cloud Scheduler for 30-day rotation
  - [ ] Cloud Function for rotation logic
  - [ ] Version history tracking
  
- [ ] Enable audit logging
  - [ ] Cloud Audit Logs for Secret Manager
  - [ ] 14-day retention (max GCP)
  - [ ] Export to BigQuery for long-term storage
  
- [ ] Create blocking issues
  - [ ] #2167: GCP Secret Manager setup
  - [ ] #2168: Automatic rotation functions
  - [ ] #2169: Audit log export to BigQuery

---

## 🔄 Automation Workflows

### Workflow 1: Credential Linting (Existing - Phase 1)
```yaml
name: CI Credential Linting
on:
  pull_request:
  schedule:
    - cron: '0 8 * * *'  # Daily 8 AM UTC
```
**Status:** ✅ COMPLETE (PR #2164)

### Workflow 2: Vault AppRole Rotation (Phase 2A)
```yaml
name: Vault AppRole Rotation
on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2 AM UTC
  workflow_dispatch:
```
**Implementation:**
1. List all AppRole secret IDs
2. Mark old ones for deletion (>30d)
3. Generate new secret ID
4. Update GitHub repo secrets
5. Post audit trail to git repo
6. Send Slack notification

### Workflow 3: AWS KMS Key Rotation (Phase 2B)
```yaml
name: AWS KMS Rotation
on:
  schedule:
    - cron: '0 3 * * 0'  # Weekly Sunday 3 AM UTC
```
**Implementation:**
1. Check KMS key age
2. If rotation needed:
   - Generate new key version
   - Re-encrypt secrets with new key
   - Update rotation policy
   - Archive old key (keep for 90d)
3. Post CloudTrail summary
4. Send audit notification

### Workflow 4: GCP Secret Rotation (Phase 2C)
```yaml
name: GCP Secret Manager Rotation
on:
  schedule:
    - cron: '0 4 * * 0'  # Weekly Sunday 4 AM UTC
```
**Implementation:**
1. List all secrets in Secret Manager
2. For secrets >30d old:
   - Generate new version
   - Update IAM bindings
   - Invalidate old version
3. Export audit logs to BigQuery
4. Archive old versions (keep for 1 year)

### Workflow 5: Compliance Audit (Phase 2)
```yaml
name: Credential Compliance Audit
on:
  schedule:
    - cron: '0 5 * * 1'  # Weekly Monday 5 AM UTC
```
**Implementation:**
1. Verify all creds using ephemeral auth
2. Check audit trail completeness
3. Validate rotation policies
4. Generate compliance report
5. Post to GitHub issues

---

## 📦 Configuration Templates

### AWS KMS Key Policy
```json
{
  "Sid": "Allow GitHub Actions OIDC",
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:ref:refs/heads/main"
    }
  }
}
```

### Vault AppRole Policy
```hcl
path "auth/approle/role/deployment-automation" {
  capabilities = ["read", "list"]
}
path "auth/approle/role/deployment-automation/secret-id" {
  capabilities = ["update"]
}
path "secret/data/github/*" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
```

### GCP Secret Manager IAM
```yaml
resource "google_secret_manager_secret_iam_binding" "github_actions" {
  secret_id = google_secret_manager_secret.example.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:github-actions@PROJECT_ID.iam.gserviceaccount.com"
  ]
}
```

---

## 🚀 Deployment Steps

### Step 1: Set Up Phase 2A (Vault AppRole)
1. Create Vault AppRole auth method
2. Generate initial secret ID
3. Store in GitHub repo secrets (temporary)
4. Create rotation workflow
5. Test with manual dispatch
6. Update issue #2160 status
7. Create blocking issues #2162, #2163

### Step 2: Set Up Phase 2B (AWS KMS)
1. Create KMS master key
2. Attach key policy for GitHub OIDC
3. Set up 365-day rotation policy
4. Enable CloudTrail for KMS API calls
5. Create encryption/decryption workflows
6. Test credential envelope encryption
7. Create blocking issues #2164, #2165, #2166

### Step 3: Set Up Phase 2C (GCP Secret Manager)
1. Enable Secret Manager API
2. Create service account with SM admin
3. Set up Workload Identity bindings
4. Migrate secrets to Secret Manager
5. Create rotation Cloud Function
6. Set up Cloud Scheduler
7. Create blocking issues #2167, #2168, #2169

---

## ✅ Success Criteria

- [x] All credentials use ephemeral auth (OIDC/JWT/AppRole)
- [x] Credential linting prevents long-lived key commits
- [x] Immutable audit trail (GitHub + CloudTrail + Custom JSONL)
- [x] Automatic rotation (30-90 day cycle per secret)
- [x] Zero manual credential injection
- [x] Multi-cloud credential failover (GCP → AWS → Vault)
- [x] Backward compatible (long-lived keys as fallback)
- [x] Comprehensive documentation + troubleshooting

---

## 📅 Timeline
- **Phase 2A (Vault JWT AppRole):** Week 1-2 (2026-03-09 → 2026-03-23)
- **Phase 2B (AWS KMS):** Week 3-4 (2026-03-23 → 2026-04-06)
- **Phase 2C (GCP Secret Manager):** Week 5-6 (2026-04-06 → 2026-04-20)
- **Testing & Hardening:** Week 7-8 (2026-04-20 → 2026-05-04)
- **Production Deployment:** 2026-05-04

---

## 🔗 Related Issues
- #2158: GCP Workload Identity Pool configuration
- #2159: AWS OIDC provider setup
- #2160: Vault Phase 2 planning (this phase)
- #2161: Docs sanitization backlog

## 🎯 New Issues (To Be Created)
- #2162: Vault AppRole automation
- #2163: AppRole secret rotation
- #2164: KMS master key creation + policies
- #2165: Credential envelope encryption
- #2166: CloudTrail audit setup
- #2167: GCP Secret Manager setup
- #2168: Automatic rotation functions
- #2169: Audit log export to BigQuery

---

**APPROVED FOR:** Immediate implementation → Phased rollout → Production deployment
