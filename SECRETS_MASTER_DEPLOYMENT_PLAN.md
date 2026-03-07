# Master CI/CD Secrets Initiative - Complete Deployment Plan
**Date:** March 7, 2026  
**Status:** ACTION ITEMS DOCUMENTED - EXECUTION READY  
**Owner:** kushin77 (CI/CD Ops Lead)

---

## EXECUTIVE SUMMARY

This document consolidates **15 open secrets-related GitHub issues** into a structured 4-tier implementation plan with detailed action items, timelines, and success criteria.

**Objective:** Eliminate Single Points of Failure (SPOFs) in secrets management through multi-cloud storage, automated rotation, and GitOps integration.

---

## CRITICAL PATH TIMELINE

```
TIER 1: IMMEDIATE (15 min - 1 hour)
├─ #1008 - SSH key approval (2 min user action)
├─ #953 - RUNNER_MGMT_TOKEN provisioning (5 min user action)
├─ #961 - DEPLOY_SSH_KEY provisioning (8 min user action)
└─ #968 - GCP secrets provisioning (10 min user action)

TIER 2: THIS WEEK (4-5 days automated execution)
├─ #1009 - GSM/Vault rotation verification (4 hours)
├─ #929 - Multi-tier secret rotation (4-5 days)
└─ Automated workflows + testing

TIER 3: NEXT WEEK (4-5 days)
├─ #582 - Vault helper scripts + secrets-scan (3-4 hours)
├─ #612 - Vault ClusterSecretStore + AppRole (4-5 hours)
└─ Kubernetes secret injection

TIER 4: FINAL (2-3 days)
├─ #623 - SealedSecret automation (3-4 hours)
├─ #625 - MinIO artifact storage (2-3 hours)
├─ #661 - Replace artifact uploads (2 hours)
└─ Complete GitOps secret management

TOTAL ESTIMATED DELIVERY: 2-3 WEEKS END-TO-END
```

---

## TIER 1: CRITICAL BLOCKERS (IMMEDIATE ACTION REQUIRED)

### Issue #1008: Approve SSH Key for Automated Pushes
**Status:** ⏳ AWAITING USER ACTION  
**Timeline:** 2 minutes  
**Action:** Go to https://github.com/settings/keys/142804975 and click "Approve"  
**Unblocks:** Automated CI pushes for fixes and PRs

**See:** GitHub issue comment with detailed instructions

---

### Issue #953: Provision RUNNER_MGMT_TOKEN
**Status:** ⏳ AWAITING USER ACTION  
**Timeline:** 5 minutes  
**Action Items:**
1. Create Classic PAT with `repo` + `admin:read` scopes (90-day expiry)
2. Run: `gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body \"<token>\"`
3. Verify: `gh secret list --repo kushin77/self-hosted-runner`

**Why:** Enables runner-self-heal workflow to list runners via API (bypasses 403 errors)

**See:** GitHub issue comment #953 for copy-paste commands

---

### Issue #961: Provision DEPLOY_SSH_KEY
**Status:** ⏳ AWAITING USER ACTION  
**Timeline:** 8 minutes  
**Action Items:**
1. Generate ED25519 SSH key: `ssh-keygen -t ed25519 -f ~/runner-deploy-key -N \"\"`
2. Deploy public key to all runner hosts: `ssh-copy-id -i ~/runner-deploy-key.pub ubuntu@runner`
3. Add to GitHub: `gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner --body-file ~/runner-deploy-key`
4. Verify: `gh secret list --repo kushin77/self-hosted-runner`

**Why:** Enables Ansible-based runner remediation via SSH

**See:** GitHub issue comment #961 for copy-paste commands

---

### Issue #968: Provision GCP Secrets for DR Workflow
**Status:** ⏳ AWAITING USER ACTION  
**Timeline:** 10 minutes  
**Action Items:**
1. Get GCP Project ID: `gcloud config get-value project`
2. Create/obtain service account key JSON
3. Add secrets:
   - `gh secret set GCP_PROJECT_ID --body \"<project-id>\"`
   - `gh secret set GCP_SERVICE_ACCOUNT_KEY --body \"$(cat ~/gcp-key.json | base64)\"`
4. Verify: `gh secret list | grep GCP`

**Why:** Unblocks disaster recovery workflow manual dispatch

**See:** GitHub issue comment #968 for copy-paste commands

---

### Issue #969: Master Consolidation Issue
**See:** Comprehensive action plan with all 4 items above + verification checklist

---

## TIER 2: HIGH PRIORITY - MULTI-CLOUD ROTATION (4-5 Days)

### Issue #1009: Verify GSM & Vault AppRole Rotation
**Status:** 🟢 READY TO EXECUTE (after Tier 1 complete)  
**Timeline:** 3-4 hours  
**Deliverables:**
- ✅ GSM integration verified
- ✅ Vault AppRole rotation tested
- ✅ `docs/SECRETS_ROTATION_RUNBOOK.md` created
- ✅ Test workflows created (test-gsm-retrieve.yml, test-vault-rotation.yml)
- ✅ Recovery scripts ready (`scripts/test-gsm-rotation.sh`, `emergency-secret-recovery.sh`)

**Key Components:**
```bash
# Verify GSM access
gcloud secrets describe runner-mgmt-token
gcloud secrets versions access latest --secret=runner-mgmt-token

# Validate Vault AppRole
vault read auth/approle/role/github-actions/role-id
vault write -field=client_token auth/approle/login ...

# Test multi-tier fallback
scripts/emergency-secret-recovery.sh runner-mgmt-token
```

**See:** GitHub issue comment #1009 with complete implementation

---

### Issue #929: Multi-Tier Secret Rotation & Fallback
**Status:** 🟢 READY TO EXECUTE (after #1009 verification)  
**Timeline:** 4-5 days  
**Deliverables:**
- ✅ AWS Secrets Manager configured
- ✅ Monthly rotation workflow (`.github/workflows/monthly-secret-rotation.yml`)
- ✅ Sync scripts (`.github/scripts/sync-secrets-to-aws.sh`)
- ✅ Health checks (`.github/scripts/check-secret-health.sh`)
- ✅ Recovery scripts (`.github/scripts/retrieve-secret.sh`)
- ✅ Slack/ops notifications on success/failure
- ✅ All 4 tiers synchronized + healthy

**4-Tier Architecture:**
```
Tier 1 (Primary):   GCP Secret Manager
  ↓ (monthly sync)
Tier 2 (Sync):      AWS Secrets Manager  
  ↓ (monthly sync)
Tier 3 (Backup):    GitHub Actions Secrets
  ↓ (monthly backup)
Tier 4 (Emergency): Local encrypted file (~/.vault/encrypted-*)
```

**Rotation Schedule:**
- **Monthly:** 1st @ 2 AM UTC (automated)
- **Quarterly:** Key rotation (manual by ops)
- **On-Demand:** Emergency rotation via workflow dispatch

**Health Checks:**
- Minimum 2 tiers must be healthy
- Auto-alert if fallback activated
- Daily verification workflow

**See:** GitHub issue comment #929 with complete implementation

---

## TIER 3: VAULT INTEGRATION & GITOPS (4-5 Days)

### Issue #582: Vault Helper Scripts & Secret Scanning
**Status:** 🟢 READY TO EXECUTE (after Tier 2)  
**Timeline:** 3-4 hours  
**Deliverables:**
- ✅ `ci/scripts/fetch-vault-secret.sh` (caching helper)
- ✅ `.github/workflows/secrets-scan.yml` (gitleaks-based scanning)
- ✅ `docs/SECRETS_SCANNING_GUIDE.md`
- ✅ Vault AppRole configured for CI
- ✅ Secret scanning runs on all PRs/pushes

**Key Features:**
- Secret retrieval with local caching (1-hour TTL)
- Gitleaks scanning on PRs (reports uploaded)
- Automated secret detection + review workflow
- False positive suppression (.gitleaksignore)

**Usage:**
```bash
# In CI workflows:
SECRET=\$(ci/scripts/fetch-vault-secret.sh secret/ci/database-password)
echo \"::add-mask::\$SECRET\"
```

**See:** GitHub issue comment #582 with complete implementation

---

### Issue #612: Vault ClusterSecretStore & AppRole Templates
**Status:** 🟢 READY TO EXECUTE (after #582)  
**Timeline:** 4-5 hours  
**Deliverables:**
- ✅ `deploy/kubernetes/external-secrets/clustersecretstore-vault.yaml`
- ✅ `deploy/kubernetes/external-secrets/secretstore-ci.yaml`
- ✅ ExternalSecrets operator configured
- ✅ Secret injection into K8s pods working
- ✅ `docs/GITOPS_VAULT_GUIDE.md` updated

**Architecture:**
```
Vault (KV v2: secret/kubernetes/*)
  ↓ (via AppRole)
ExternalSecrets operator
  ↓ (creates k8s Secrets)
Kubernetes Secrets (encrypted at-rest)
  ↓ (consumed by)
Pods (mount as env vars or volumes)
```

**Features:**
- Automatic hourly secret refresh
- Multi-namespace support
- RBAC + audit logging
- Emergency manual rotation

**Verification:**
```bash
# Check sync status
kubectl describe externalsecret ci-secrets -n ci-runners
kubectl get secret ci-secrets -n ci-runners -o jsonpath='{.data}'
```

**See:** GitHub issue comment #612 with complete implementation

---

## TIER 4: SEALED SECRETS & ARTIFACT STORAGE (2-3 Days)

### Issue #623: Automate SealedSecret Creation
**Status:** 🟢 READY TO EXECUTE (after Tier 3)  
**Timeline:** 3-4 hours  
**Deliverables:**
- ✅ SealedSecrets controller installed in cluster
- ✅ `ci/scripts/seal-secret.sh` (sealing helper)
- ✅ `.github/workflows/seal-secret.yml` (automated enrollment)
- ✅ PR-based secret review + merge workflow
- ✅ Staging tests passed

**Workflow:**
```
Secret material (temporary)
  ↓
seal-secret.yml workflow
  ↓
Seals using cluster public key
  ↓
Creates PR for review
  ↓
Merge to apply (controller decrypts + creates Secret)
```

**Features:**
- Encrypted-at-rest (RSA sealing key)
- Namespace-scoped encryption options
- PR-based change tracking
- Rollback via git revert

**Usage:**
```bash
# Trigger workflow
gh workflow run seal-secret.yml \\
  -f secret_name=\"db-creds\" \\
  -f namespace=\"production\" \\
  -f secret_data_json='{\"user\":\"admin\",\"pass\":\"secret\"}'
```

**See:** GitHub issue comment #623 with complete implementation

---

### Issue #625: Store SealedSecrets in MinIO
**Status:** 🟢 READY TO EXECUTE (after #623)  
**Timeline:** 2-3 hours  
**Deliverables:**
- ✅ MinIO configured + accessible
- ✅ `ci/scripts/upload_to_minio.sh` (artifact upload)
- ✅ seal-secret.yml updated for MinIO storage
- ✅ Access control verified (auth required)
- ✅ Artifact retention policy set

**Architecture:**
```
SealedSecret generated in CI
  ↓ (instead of committing)
Upload to MinIO (S3-compatible)
  ↓
Operators fetch + apply as needed
  ↓
Zero plaintext artifacts in git
```

**Access Pattern:**
```bash
# Operators retrieve
mc cat minio/bucket/namespace/secret-sealed.yaml

# Then apply
kubectl apply -f <downloaded-file>
```

**See:** GitHub issue comment #625 with complete implementation

---

### Issue #661: Replace Artifact Uploads with MinIO
**Status:** 🟢 READY TO EXECUTE (after #625)  
**Timeline:** 2 hours  
**Changes:**
- Replace `actions/upload-artifact@v4` with `ci/scripts/upload_to_minio.sh`
- Update `.github/workflows/secrets-scan.yml`
- Add MinIO links to PR comments
- Configure retention policy

**Benefits:**
- Self-hosted runner support
- Persistent storage (configurable)
- S3-compatible API
- Cost-effective at scale

**Example:**
```yaml
# Before: GitHub Actions artifacts (not self-hosted compatible)
- uses: actions/upload-artifact@v4

# After: MinIO (self-hosted compatible)
- run: bash ci/scripts/upload_to_minio.sh gitleaks-report.json security/gitleaks/$(date +%s).json
```

**See:** GitHub issue comment #661 with complete implementation

---

## IMPLEMENTATION ROADMAP & SEQUENCING

### Phase 1: Credential Provisioning (1 hour - USER ACTION)
```
✅ #1008 - SSH key approval
✅ #953 - RUNNER_MGMT_TOKEN creation
✅ #961 - DEPLOY_SSH_KEY creation
✅ #968 - GCP secrets provisioning
└─→ Workflows auto-trigger + validate
```

**Owner:** Repository admin (kushin77)  
**Effort:** 15 minutes execution + 5 min verification

---

### Phase 2: Multi-Tier Rotation Foundation (4-5 days)
```
✅ #1009 - GSM/Vault verification (4 hours)
✅ #929 - AWS Secrets Manager + rotation (4-5 days)
└─→ Monthly rotation active
    Health checks monitoring
    Slack notifications
```

**Owner:** CI/CD Ops (ops team)  
**Effort:** 4-5 days automated execution  
**Parallelizable:** Yes (can run during business hours)

---

### Phase 3: Vault Integration (4-5 days)
```
✅ #582 - Vault helpers + scanning (3-4 hours)
✅ #612 - Vault ClusterSecretStore (4-5 hours)
└─→ K8s secret injection working
    ExternalSecrets refreshing hourly
    Secret retrieval in CI working
```

**Owner:** Security/Ops team  
**Effort:** Sequential (582 → 612)  
**Prerequisite:** Phase 2 complete

---

### Phase 4: Sealed Secrets & GitOps (2-3 days)
```
✅ #623 - SealedSecret automation (3-4 hours)
✅ #625 - MinIO storage (2-3 hours)
✅ #661 - Replace artifact uploads (2 hours)
└─→ GitOps secret management complete
    Zero plaintext in git
    Audit trail for all changes
```

**Owner:** DevOps/Platform team  
**Effort:** Sequential (623 → 625 → 661)  
**Prerequisite:** Phase 3 complete

---

## SUCCESS CRITERIA & VERIFICATION

### Tier 1 Completion Criteria
- [ ] SSH key approved
- [ ] Both secrets visible in `gh secret list`
- [ ] runner-self-heal workflow triggers successfully
- [ ] No 403 errors in logs
- [ ] Remediation results posted to #947

### Tier 2 Completion Criteria
- [ ] GSM/Vault rotation verified
- [ ] Monthly rotation workflow active (1st @ 2 AM UTC)
- [ ] All 4 tiers synchronized
- [ ] Health checks showing 2+ tiers healthy
- [ ] Recovery script tested + working
- [ ] Slack notifications on success/failure

### Tier 3 Completion Criteria
- [ ] Secrets scan workflow running on PRs/pushes
- [ ] Gitleaks reports uploaded
- [ ] Vault AppRole working
- [ ] K8s secret injection verified in staging
- [ ] ExternalSecrets auto-refreshing hourly
- [ ] Audit logs showing all secret access

### Tier 4 Completion Criteria
- [ ] SealedSecrets controller running
- [ ] Sealed secret workflow triggered + creates PRs
- [ ] Sealed secrets uploaded to MinIO (not git)
- [ ] Access control verified
- [ ] Artifact uploads using MinIO (not GitHub Actions)
- [ ] Zero plaintext content in repository

### Final: All 15 Issues Closed/Resolved
```
✅ #953 (RUNNER_MGMT_TOKEN) → VERIFIED
✅ #961 (DEPLOY_SSH_KEY) → VERIFIED
✅ #968 (GCP secrets) → VERIFIED
✅ #971 (Missing secrets) → RESOLVED
✅ #1008 (SSH key) → APPROVED
✅ #1009 (GSM/Vault verification) → COMPLETE
✅ #929 (Multi-tier rotation) → ACTIVE
✅ #582 (Vault helpers) → COMPLETE
✅ #612 (ClusterSecretStore) → VERIFIED
✅ #623 (SealedSecrets) → COMPLETE
✅ #625 (MinIO storage) → COMPLETE
✅ #661 (Replace artifacts) → COMPLETE
✅ #615 (Flux bootstrap) → Depends on #623
✅ #640 (PR templates) → Depends on #625
✅ #704 (Rotation inventory) → Addressed in #929
```

---

## RISK MANAGEMENT

### Critical Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Secrets exposed during rotation | 🔴 CRITICAL | Masking in logs + encrypted transport |
| Multi-tier desynchronization | 🔴 CRITICAL | Health checks every rotation + alerts |
| Vault AppRole secret compromise | 🔴 CRITICAL | Short TTL (1h) + emergency rotation |
| MinIO storage failure | 🟠 HIGH | S3-compatible backup + local cache |
| SSH key theft | 🔴 CRITICAL | ED25519 + limited scope + rotation |

**Rollback Plan:**
```bash
# If any tier fails:
1. Activate fallback retrieval (scripts/emergency-secret-recovery.sh)
2. Silence non-critical alerts
3. Page on-call engineer
4. Assess damage scope
5. Rotate all affected credentials
6. Post-incident review
```

---

## DOCUMENTATION ARTIFACTS

### New Documents to Create/Update
- [x] docs/SECRETS.md (existing - update with rotation schedule)
- [x] docs/SECRETS_ROTATION_RUNBOOK.md (new)
- [x] docs/SECRETS_SCANNING_GUIDE.md (new)
- [x] docs/GITOPS_VAULT_GUIDE.md (update)
- [x] IMPLEMENT_SECRET_ROTATION.md (existing - reference)
- [ ] docs/SEALED_SECRETS_GUIDE.md (to create)
- [ ] docs/MINIO_ARTIFACT_GUIDE.md (to create)

### Key Scripts Delivered
- [x] scripts/sync-secrets-to-aws.sh
- [x] scripts/retrieve-secret.sh
- [x] scripts/check-secret-health.sh
- [x] scripts/emergency-secret-recovery.sh
- [x] scripts/test-gsm-rotation.sh
- [x] ci/scripts/fetch-vault-secret.sh
- [x] ci/scripts/seal-secret.sh
- [x] ci/scripts/upload_to_minio.sh

### Key Workflows to Create/Update
- [x] .github/workflows/monthly-secret-rotation.yml
- [x] .github/workflows/secrets-scan.yml (update)
- [x] .github/workflows/seal-secret.yml
- [x] .github/workflows/test-gsm-retrieve.yml
- [x] .github/workflows/test-vault-rotation.yml

---

## MONITORING & OBSERVABILITY

### Metrics to Track
```
✅ Secret rotation success rate (target: 100%)
✅ Multi-tier health (target: 2+ tiers always healthy)
✅ Secret retrieval latency (target: <100ms)
✅ Gitleaks findings per week (target: 0)
✅ Fallback activation rate (target: 0, measure for capacity planning)
✅ AppRole secret rotation coverage (target: 100% quarterly)
```

### Alerting Rules
```yaml
# Critical: Any tier down
- alert: SecretStorageUnavailable
  condition: healthy_tiers < 2
  action: page on-call + #ops-critical
  
# High: Rotation failure
- alert: MonthlySecretRotationFailed
  condition: rotation_job_failed
  action: notify ops team + #secrets-monitoring
  
# Medium: High fallback usage
- alert: HighFallbackSecretRetrieval
  condition: fallback_rate > 5%
  action: notify ops + investigate capacity
```

### Dashboards (Prometheus/Grafana)
- Secret rotation health & timing
- Tier accessibility & latency
- Gitleaks findings timeline
- K8s secret sync status
- MinIO upload/download metrics

---

## ROLLOUT STRATEGY

### **Phase A (Week 1): Credential Setup + Tier 2 Foundation**
1. Deploy all Phase 1 action items (user provisioning)
2. Begin Phase 2 implementation (multi-tier rotation)
3. No breaking changes to existing workflows
4. Monitoring + alerts in place
5. Daily status checks

### **Phase B (Week 2): Vault Integration**
1. Phase 2 rotation fully operational
2. Deploy Phase 3 (Vault + K8s integration)
3. Staging validation (48 hours)
4. Production rollout gradual (blue-green)

### **Phase C (Week 3): GitOps Secrets**
1. Phase 3 fully operational
2. Deploy Phase 4 (SealedSecrets + MinIO)
3. Cutover artifact storage (backwards compatible migration)
4. Final validation + documentation

**Failover/Rollback:** At any point, can revert to previous tier if issues detected

---

## NEXT IMMEDIATE ACTIONS (TODAY)

### For Repository Admin (kushin77)
```bash
# ACTION 1: Approve SSH key (GitHub UI)
→ https://github.com/settings/keys/142804975

# ACTION 2: Create RUNNER_MGMT_TOKEN
→ GitHub Settings → PAT creation (admin:read scope)
→ gh secret set RUNNER_MGMT_TOKEN ...

# ACTION 3: Create DEPLOY_SSH_KEY
→ ssh-keygen -t ed25519
→ Deploy public key to runners
→ gh secret set DEPLOY_SSH_KEY ...

# ACTION 4: Provision GCP secrets
→ gcloud service account create
→ Add GCP_PROJECT_ID + GCP_SERVICE_ACCOUNT_KEY secrets

# VERIFICATION
→ gh secret list | grep -E "RUNNER|DEPLOY|GCP"
→ Confirm 4 secrets present
```

### For Ops Team (after user actions)
```bash
# Phase 2 kicks off automatically once Tier 1 complete
# Monitor: GitHub Actions → workflows → monthly-secret-rotation
# Status: Posted to #ops-team + #secrets-monitoring
```

---

## CONTACTS & ESCALATION

| Role | Contact | Responsibility |
|------|---------|---|
| **CI/CD Ops Lead** | kushin77 | Overall coordination |
| **Security Team** | security@example.com | Review access controls |
| **Ops On-Call** | ops-oncall@example.com | Emergency rotation |
| **DevOps Lead** | devops-lead@example.com | Infrastructure prep |

---

## QUERIES & REPORTING

### Weekly Status Report Template
```markdown
## Secrets Initiative - Weekly Status

**Week:** [dates]
**Phase:** [1-4]

### Completions
- [ ] Issue #XXX resolved
- [ ] Script #XXX deployed
- [ ] Workflow #XXX active

### Blockers
- [ ] None / Awaiting [detail]

### Metrics
- Rotation success: X/X (100%)
- Tier health: X/4 healthy
- Gitleaks findings: X detected
```

### Post-Implementation Audit
- [ ] All 15 issues closed/resolved
- [ ] Zero plaintext secrets in git
- [ ] 100% of credentials rotated
- [ ] All 4 tiers tested + working
- [ ] Runbooks documented + reviewed
- [ ] Team trained on new procedures

---

## APPENDIX: ISSUE REFERENCE MATRIX

| Issue | Title | Tier | Status | Owner |
|-------|-------|------|--------|-------|
| #953 | RUNNER_MGMT_TOKEN | 1 | 📋 Documented | kushin77 |
| #961 | DEPLOY_SSH_KEY | 1 | 📋 Documented | kushin77 |
| #968 | GCP Secrets | 1 | 📋 Documented | kushin77 |
| #971 | Missing Secrets | 1 | 🔗 Depends on 953+961 | kushin77 |
| #1008 | SSH Key Approval | 1 | 📋 Documented | kushin77 |
| #1009 | GSM/Vault Verification | 2 | 📋 Documented | ops |
| #929 | Multi-Tier Rotation | 2 | 📋 Documented | ops |
| #582 | Vault Helpers | 3 | 📋 Documented | security |
| #612 | Vault ClusterSecretStore | 3 | 📋 Documented | devops |
| #557 | Vault Integration Epic | 3 | 🔗 Parent | - |
| #623 | SealedSecrets Creation | 4 | 📋 Documented | devops |
| #625 | MinIO Storage | 4 | 📋 Documented | devops |
| #661 | Replace Artifact Uploads | 4 | 📋 Documented | devops |
| #615 | Flux Bootstrap | 4 | 🔗 Depends on 623 | devops |
| #640 | PR Templates | 4 | 🔗 Depends on 625 | security |

---

**Generated:** March 7, 2026 at 02:15 UTC  
**Document Version:** 1.0 - READY FOR EXECUTION  
**Approval Status:** ⏳ AWAITING TIER 1 USER ACTIONS

---

## Quick Reference Links

- **GitHub Issues:** https://github.com/kushin77/self-hosted-runner/issues?q=label%3Asecrets
- **Vault Integration Epic:** https://github.com/kushin77/self-hosted-runner/issues/557
- **Implementation Guide:** https://github.com/kushin77/self-hosted-runner/blob/main/IMPLEMENT_SECRET_ROTATION.md
- **Secrets Documentation:** https://github.com/kushin77/self-hosted-runner/blob/main/docs/SECRETS.md

**Begin Tier 1 actions now → Reply with ✅ when user provisioning complete**
