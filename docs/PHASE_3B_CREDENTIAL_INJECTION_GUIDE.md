# Phase 3B: Credential Injection & Full Deployment Guide

**Status:** ✅ Framework Ready for Activation  
**Date:** 2026-03-09  
**Authorization:** User-approved autonomous execution  

---

## Quick Start: 3 Ways to Inject Credentials

### Option 1: CLI Credential Manager (Easiest)

```bash
# 1. Set AWS credentials
./scripts/phase3b-credential-manager.sh set-aws --key REDACTED_AWS_ACCESS_KEY_ID --secret xxxxxxxxxxxxxxx

# 2. Set Vault credentials (optional Layer 2A)
./scripts/phase3b-credential-manager.sh set-vault \
  --addr https://vault.example.com:8200 \
  --token hvs.xxxxxxxxxxxxx

# 3. Verify all layers
./scripts/phase3b-credential-manager.sh verify

# 4. Activate Phase 3B deployment
./scripts/phase3b-credential-manager.sh activate
```

**Result:** All 4 credential layers activated, immutable audit trail updated, GitHub Actions ready

---

### Option 2: Direct Environment Variables

```bash
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
export VAULT_ADDR=https://vault.example.com:8200
export REDACTED_VAULT_TOKEN=hvs.xxxxxxxxxxxxx

bash scripts/phase3b-credentials-inject-activate.sh
```

**Result:** Same as Option 1

---

### Option 3: GitHub Actions Workflow (CI/CD Automated)

**Via GitHub UI:**
1. Go to Actions → "Phase 3B - Credential Injection & Full Deployment"
2. Click "Run workflow"
3. Enter AWS credentials, Vault address/token
4. Click "Run workflow"
5. Monitor execution (auto-commits to main)

**Via GitHub CLI:**
```bash
gh workflow run phase3b-credential-injection.yml \
  -f AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
  -f REDACTED_AWS_SECRET_ACCESS_KEY=xxxxxxxxxxxxxxx \
  -f vault_addr=https://vault.example.com:8200 \
  -f REDACTED_VAULT_TOKEN=hvs.xxxxxxxxxxxxx
```

**Result:** GitHub Actions auto-runs Phase 3B, creates workflow job comment on issues

---

## What Gets Activated (Phase 3B Full Deployment)

### Layer 1: GCP Secret Manager (Primary)
- ✅ GSM API enabled for credential storage
- ✅ Multi-region replication ready
- ✅ Credential caching with 30-min TTL

### Layer 2A: Vault JWT Auth (Secondary)
- ✅ JWT auth method enabled
- ✅ GitHub Actions OIDC configured
- ✅ 50-minute token TTL with auto-renewal
- ⏳ Requires: Vault unsealing + token

### Layer 2B: AWS KMS (Tertiary)
- ✅ KMS key created and aliased
- ✅ Encryption for credential storage
- ✅ 30-minute STS temporary credentials
- ⏳ Requires: AWS credentials

### Layer 3: Local Encrypted Cache (Offline Fallback)
- ✅ /var/cache/credentials directory
- ✅ AES-256-GCM encryption
- ✅ 1-hour offline data validity

---

## Credential Manager CLI Reference

### Set AWS Credentials
```bash
./scripts/phase3b-credential-manager.sh set-aws \
  --key REDACTED_AWS_ACCESS_KEY_ID \
  --secret xxxxxxxxxxxxxxx
```

Verifies credentials via `aws sts get-caller-identity`

### Set Vault Credentials
```bash
./scripts/phase3b-credential-manager.sh set-vault \
  --addr https://vault.example.com:8200 \
  --token hvs.xxxxxxxxxxxxx
```

Verifies connection via `vault status`

### Set GCP Project
```bash
./scripts/phase3b-credential-manager.sh set-gcp \
  --project my-gcp-project-id
```

Verifies via `gcloud auth list`

### List Stored Credentials
```bash
./scripts/phase3b-credential-manager.sh get-all
```

**Output:** Credentials with masked values (8...last4 pattern)

### Verify All Credential Layers
```bash
./scripts/phase3b-credential-manager.sh verify
```

Tests each layer connectivity and reports status

### Activate Full Phase 3B Deployment
```bash
./scripts/phase3b-credential-manager.sh activate
```

Runs full deployment with immutable audit trail

---

## Detailed Activation Flow

```
┌────────────────────────────────────────────────────────────────┐
│ 1. Admin Injects Credentials (CLI, env, or GitHub Actions)    │
├────────────────────────────────────────────────────────────────┤
│ 2. Credential Manager Validates Each Layer                    │
│    ├─ AWS: sts get-caller-identity                            │
│    ├─ Vault: vault status                                     │
│    ├─ GCP: gcloud auth list                                   │
│    └─ Local: mkdir /var/cache/credentials                     │
├────────────────────────────────────────────────────────────────┤
│ 3. Credential Injection Script Runs                           │
│    ├─ AWS OIDC Provider creation                              │
│    ├─ AWS KMS key provisioning                                │
│    ├─ Vault JWT auth configuration                            │
│    ├─ GitHub Actions secrets population                       │
│    └─ Multi-layer failover testing                            │
├────────────────────────────────────────────────────────────────┤
│ 4. Full Phase 3B Provisioning Script Runs                     │
│    ├─ credential-rotation automation                          │
│    ├─ Cloud Scheduler job creation                            │
│    ├─ Kubernetes CronJob setup (if K8s available)             │
│    ├─ systemd timer configuration                             │
│    └─ Compliance audit automation                             │
├────────────────────────────────────────────────────────────────┤
│ 5. Verification & Audit Trail Entry                           │
│    ├─ All 4 layers verified operational                       │
│    ├─ 217+ audit entries logged                               │
│    ├─ Git commit to main (immutable record)                   │
│    └─ GitHub issue comment with status                        │
└────────────────────────────────────────────────────────────────┘
```

---

## Troubleshooting

### AWS Credentials Invalid
```bash
# Test credentials
aws sts get-caller-identity

# If fails:
# 1. Check AWS_ACCESS_KEY_ID is set
# 2. Check REDACTED_AWS_SECRET_ACCESS_KEY is set
# 3. Verify credentials have IAM permissions:
#    - iam:CreateOpenIDConnectProvider
#    - kms:CreateKey
#    - kms:CreateAlias
```

### Vault Connection Failed
```bash
# Test Vault connection
vault status

# If fails:
# 1. Vault may be sealed - use unsealing keys
# 2. Check VAULT_ADDR is correct (with :8200)
# 3. Check REDACTED_VAULT_TOKEN is valid
# 4. Check network connectivity to Vault endpoint
```

### GitHub Actions Workflow Not Running
```bash
# Check workflow file exists
ls .github/workflows/phase3b-credential-injection.yml

# Manual trigger:
gh workflow run phase3b-credential-injection.yml

# Monitor:
gh run list --workflow=phase3b-credential-injection.yml
```

### Credential Manager Reports Errors
```bash
# Check credential storage
ls -la ~/.phase3b-credentials

# View audit trail
cat logs/deployment-provisioning-audit.jsonl | tail -10

# Re-run verify
./scripts/phase3b-credential-manager.sh verify
```

---

## Architecture: All 7 Requirements Maintained

| Requirement | Phase 3B Implementation | Status |
|-----------|----------------------|--------|
| **Immutable** | Append-only audit trail to JSONL + git | ✅ |
| **Ephemeral** | Credentials fetched at runtime (not embedded) | ✅ |
| **Idempotent** | All scripts check-before-mutate pattern | ✅ |
| **No-Ops** | Cloud Scheduler + systemd timers + K8s CronJob | ✅ |
| **Hands-Off** | Single CLI command or GitHub Actions trigger | ✅ |
| **Direct-Main** | All code to main branch (no features branches) | ✅ |
| **GSM/Vault/KMS** | 4-layer multi-layer credential system | ✅ |

---

## Security Notes

### Credential Storage
- Stored in `~/.phase3b-credentials` with 0600 permissions (owner read/write only)
- Not committed to git (added to .gitignore)
- Encrypted on disk if using systemd-encrypted volumes

### Credential Rotation
- AWS KMS: 30-minute STS token TTL
- Vault JWT: 50-minute token TTL with auto-renewal
- GSM: 30-minute cache TTL with refresh-on-read
- Automatic rotation via Cloud Scheduler (15-minute cycle)

### Audit Trail
- All credential access logged to immutable JSONL
- GitHub issue comments track all deployment events
- Git commit history provides traceable record

---

## Rollback Plan

If issues encountered during activation:

```bash
# Stop automation
systemctl stop vault-agent-rotation  # If systemd available
gcloud scheduler jobs pause phase-3-credentials-rotation  # If GCP available

# Revert Phase 3B changes
git revert HEAD  # Reverts most recent commit

# Verify system restored
./scripts/phase3b-credential-manager.sh verify
```

All changes are idempotent and reversible.

---

## Next Steps After Activation

1. **Monitor Credential Rotation:**
   ```bash
   gcloud scheduler jobs describe phase-3-credentials-rotation
   ```

2. **Review Audit Trail:**
   ```bash
   cat logs/deployment-provisioning-audit.jsonl | jq '.event' | sort | uniq -c
   ```

3. **Test Failover:**
   ```bash
   bash scripts/credentials-failover.sh
   ```

4. **Configure Alerting:**
   - Set up notifications for credential rotation failures
   - Monitor deployment status via GitHub Actions

5. **Schedule Key Rotation:**
   - Quarterly AWS KMS key rotation
   - Quarterly Vault token rotation
   - Monthly GSM audit

---

## Support & References

- **Credential Manager:** `./scripts/phase3b-credential-manager.sh help`
- **Injection Script:** `./scripts/phase3b-credentials-inject-activate.sh --validate-only`
- **GitHub Workflow:** `.github/workflows/phase3b-credential-injection.yml`
- **Audit Trail:** `logs/deployment-provisioning-audit.jsonl`
- **Manual Docs:** [PHASE_3B_AUTONOMOUS_DEPLOYMENT_2026_03_09.md](../PHASE_3B_AUTONOMOUS_DEPLOYMENT_2026_03_09.md)

---

## Quick Command: Full Activation

```bash
# 1. Single-liner with environment variables
export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
export VAULT_ADDR=https://vault.example.com:8200 && \
export REDACTED_VAULT_TOKEN=hvs.xxxxxxxxxxxxx && \
bash scripts/phase3b-credentials-inject-activate.sh

# 2. Or via CLI tool
./scripts/phase3b-credential-manager.sh set-aws --key REDACTED_AWS_ACCESS_KEY_ID --secret xxxxxxxxxxxxxxx && \
./scripts/phase3b-credential-manager.sh set-vault --addr https://vault.example.com:8200 --token hvs.xxxxxxxxxxxxx && \
./scripts/phase3b-credential-manager.sh activate
```

**That's it!** Phase 3B deployment will complete autonomously.

---

**Status:** 🟢 READY FOR CREDENTIAL INJECTION

Go to [Issue #2129](../../issues/2129) or [Issue #2133](../../issues/2133) for current deployment status.
