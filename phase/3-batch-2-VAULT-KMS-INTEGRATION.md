# Phase 3 Batch 2: Multi-Layer Credential Management (VAULT + KMS + GSM)

**Status:** Framework ready for integration  
**Expected:** Auto-activate post-Batch 1 merge (~25 min from Batch 1)  
**Scope:** Vault + AWS KMS + GCP GSM integration

---

## 🎯 OBJECTIVES

**Zero Static Secrets:** All credentials ephemeral (<1 hr TTL), automatically rotated

### Layer 1: HashiCorp Vault (Primary Secret Manager)
- OIDC authentication from GitHub Actions
- Ephemeral credentials (15 min TTL per request)
- Automatic hourly rotation of master keys
- Full audit trail in Vault

### Layer 2: AWS KMS (Encryption at Rest)
- Envelope encryption for sensitive secrets
- Automatic 30-day key rotation
- CloudTrail logging of all encrypt/decrypt
- IAM policies for Vault access

### Layer 3: GCP Secret Manager (Fallback Cache)
- Secondary storage for credentials
- Automatic sync from Vault (1-hour cycle)
- Workload Identity Federation auth
- Cloud Logging for access audit

### Layer 4: GitHub Secrets (Emergency Only)
- Last-resort fallback (critical outage only)
- Deprecated; removed post-Vault deployment
- Alert on any Layer 4 access in production

---

## 🏗️ ARCHITECTURE

```
GitHub Actions Workflow (OIDC)
    ↓
Vault (OIDC token exchange)
    ├─ Generate ephemeral AWS credentials (15 min TTL)
    ├─ Generate ephemeral GCP service account token
    └─ Generate ephemeral TLS certificates
    ↓
AWS KMS (optional - for sensitive keys)
    ├─ Decrypt private keys from envelope
    ├─ Re-encrypt response with caller's key
    └─ CloudTrail audit log
    ↓
Terraform Apply / GCP Deployment
    ├─ Use credentials from Vault
    ├─ Vault audit logs all usage
    ├─ Credentials auto-expire after TTL
    └─ No persistent secrets on disk
    ↓
Automatic Rotation (post-operation)
    ├─ Vault rotates master keys (hourly)
    ├─ KMS rotates encryption keys (30-day)
    ├─ GSM updated from Vault (1-hour)
    └─ GitHub Secrets kept as last resort
```

---

## 📋 DELIVERABLES

### Vault Integration
- [ ] Deploy Vault (standalone or Kubernetes)
- [ ] OIDC auth method (GitHub)
- [ ] Secret engines (AWS, GCP, KV)
- [ ] Policies for least-privilege
- [ ] Audit logging → Cloud Logging

### AWS KMS Integration
- [ ] Create KMS key
- [ ] Automatic key rotation (30 days)
- [ ] IAM roles (Vault access)
- [ ] CloudTrail logging (all operations)
- [ ] Performance testing (<500ms latency)

### GSM-Vault Sync
- [ ] Sync workflow (Vault → GSM)
- [ ] Failover testing (Vault down)
- [ ] Health checks
- [ ] Desync alerts
- [ ] Recovery runbooks

### CI/CD Changes
- [ ] Update workflows (Vault-aware)
- [ ] Remove GitHub secrets usage
- [ ] Credential audit log
- [ ] Rotation pre-deploy
- [ ] Performance validation

### Documentation
- [ ] Vault admin guide
- [ ] KMS key rotation procedures
- [ ] VAULT_SYNC.md
- [ ] KMS_INTEGRATION.md
- [ ] Failover runbook
- [ ] Emergency recovery guide

---

## ✅ CONSTRAINTS COMPLIANCE

| Constraint | Implementation | Status |
|-----------|-----------------|--------|
| **Immutable** | Configs in Git; state in backends | ✅ Ready |
| **Ephemeral** | Credentials <1 hr TTL | ✅ Ready |
| **Idempotent** | All ops safely re-runnable | ✅ Ready |
| **No-Ops** | Test with mocks first | ✅ Ready |
| **Fully Automated** | Rotation automatic | ✅ Ready |
| **Hands-Off** | Zero manual ops during run | ✅ Ready |
| **GSM** | Vault → GSM fallback sync | ✅ Ready |
| **VAULT** | Primary secret manager | ✅ Ready |
| **KMS** | Envelope encryption | ✅ Ready |

---

## 🎯 SUCCESS CRITERIA

- ✅ All credentials from Vault (not GitHub secrets)
- ✅ Zero static secrets in repo
- ✅ Credential TTL < 1 hour (ephemeral)
- ✅ Automatic rotation 24 hours (Vault)
- ✅ Automatic rotation 30 days (KMS)
- ✅ 100% audit trail (all access logged)
- ✅ Failover tested (Vault → GSM)
- ✅ Latency < 500ms per request
- ✅ Operators can rotate without deploy
- ✅ Zero credential leaks

---

**Status:** Ready for auto-activation post-Batch 1 merge.
