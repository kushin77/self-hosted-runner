# GO-LIVE OPERATIONAL GUIDE — March 9, 2026

**Status: ✅ PRODUCTION READY FOR FIRST DEPLOYMENT**

---

## Executive Summary

All infrastructure is deployed, tested, and waiting for operator action. **The deployment system is fully automated and requires zero manual intervention after credential provisioning.**

---

## Current System State

### ✅ Infrastructure Components

| Component | Status | Details |
|-----------|--------|---------|
| **Direct-Deploy** | ✅ Ready | `/opt/app/direct-deploy.sh` deployed on worker |
| **Watcher Service** | ✅ Active | Running on bastion, polling every 30 seconds |
| **Systemd Unit** | ✅ Enabled | Auto-restart configured, persistent across reboot |
| **SSH Keys** | ✅ Generated | `/opt/self-hosted-runner/.ssh/runner_ed25519` (private+public) |
| **Audit Trail** | ✅ Ready | GitHub #2072 + JSONL fallback configured |
| **Documentation** | ✅ Complete | 5 comprehensive guides ready |

### ✅ Enterprise Guarantees Implemented

- ✅ **Immutable** — Append-only audit (no data loss, permanent record)
- ✅ **Ephemeral** — Credentials destroyed post-deployment
- ✅ **Idempotent** — Git bundle prevents state corruption
- ✅ **Hands-Off** — Systemd watcher auto-triggers deployments
- ✅ **Multi-Cred** — GSM/Vault/AWS support (all 3 implemented)
- ✅ **Zero CI/CD** — All workflows archived, Dependabot disabled
- ✅ **Direct-Deploy-Only** — No PR-based workflows allowed

---

## Operator: Your Single Required Action

### Step 1: Provision SSH Credentials

You have **three options**. Choose one (all are equally supported):

#### Option A: Google Secret Manager (Recommended)
```bash
# Grant operator account Secret Manager access
gcloud projects add-iam-policy-binding elevatediq-runner \
  --member=user:kushin77@gmail.com \
  --role=roles/secretmanager.viewer

# Provision the SSH key to GSM
bash scripts/deploy-operator-credentials.sh gsm
```

#### Option B: HashiCorp Vault
```bash
# Requires Vault server address and auth token
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="your-token"

bash scripts/deploy-operator-credentials.sh vault
```

#### Option C: AWS Secrets Manager
```bash
# Requires AWS credentials configured
export AWS_REGION="us-east-1"
aws configure  # (if not already configured)

bash scripts/deploy-operator-credentials.sh aws
```

---

## Automated Deployment Flow (Happens Automatically)

**Once you run the provisioning command above:**

### Timeline: 0-5 Minutes

```
T+0s   → Watcher detects credentials in selected provider
         (polling checks every 30 seconds)

T+0-30s → Auto-triggers direct-deploy.sh
          (no manual intervention needed)

T+0-60s → Creates immutable git bundle (SHA256 hash)
          Size: ~650-700 MB (varies)

T+60-90s → Transfers bundle via SCP to 192.168.168.42
           Speed: ~100 MB/s

T+90-120s → Unpacks bundle on target worker
            Git checkout of main branch

T+120-150s → Posts audit entry to GitHub issue #2072
             Includes: timestamp, SHA256, deployment result

T+180s → Destroys ephemeral credentials (cleanup trap)
         System returns to polling

T+180s+ → System ready for next deployment
```

---

## Monitoring Deployment Progress

### Real-Time Monitoring (While Deployment Runs)

```bash
# Option 1: Watch watcher service logs
ssh akushnir@192.168.168.42 'sudo journalctl -u wait-and-deploy.service -f'

# Option 2: Check watcher service status
ssh akushnir@192.168.168.42 'systemctl status wait-and-deploy.service'

# Option 3: Monitor direct-deploy logs
ssh akushnir@192.168.168.42 'tail -f /opt/self-hosted-runner/logs/deployment-verification-audit.jsonl'
```

### Audit Trail Verification

```bash
# Check GitHub issue #2072 for immutable audit entries
# Each deployment posts an entry with full details

gh issue view 2072 --repo kushin77/self-hosted-runner
```

### Deployment Success Indicators

✅ **Success signals:**
- Audit entry posted to GitHub #2072 with `status=SUCCESS`
- JSONL log file updated with deployment details
- Worker node has latest code in `/opt/self-hosted-runner`
- Watcher service returns to polling state

❌ **Failure signals:**
- Watcher logs show repeated errors (check credential access)
- Deployment timeout after 3 hours (MAX_ATTEMPTS=360)
- Audit entry posted with `status=FAILED` and error details

---

## Production Deployment Sequence (Auto-Executed)

### Phase 1: Credential Fetch (T+0-10s)
- Watcher detects credentials
- direct-deploy.sh fetches credentials from GSM/Vault/AWS
- Credentials loaded into shell variables (ephemeral)

### Phase 2: Bundle Creation (T+10-60s)
- Creates immutable git bundle of main branch
- Generates SHA256 hash for integrity verification
- Bundle stored in `/tmp/deploy-TIMESTAMP.bundle`

### Phase 3: Transfer (T+60-90s)
- SCP transfers bundle to `192.168.168.42:/tmp/`
- Transfer logged with timestamp and file size
- Target verifies file received

### Phase 4: Deploy (T+90-120s)
- Remote checkout of bundle
- Git initializes repository on target
- Checks out main branch (safe, idempotent operation)

### Phase 5: Audit (T+120-150s)
- Posts audit entry to GitHub #2072
- Includes: deployment time, SHA256, result, operator
- JSONL backup log created locally

### Phase 6: Cleanup (T+150-180s)
- Shell trap destroys all credential variables
- Temporary bundle files removed
- System returns to polling state

---

## Troubleshooting Guide

### Issue: Deployment doesn't start after provisioning

**Symptoms:** Watcher still polling without triggering deployment

**Troubleshooting:**
```bash
# 1. Verify credentials are in provider
gcloud secrets list --project=elevatediq-runner  # For GSM
vault kv get secret/runner-deploy               # For Vault
aws secretsmanager describe-secret               # For AWS

# 2. Check watcher logs
ssh akushnir@192.168.168.42 'sudo journalctl -u wait-and-deploy.service -n 100'

# 3. Manually test credential detection
ssh akushnir@192.168.168.42 'gcloud secrets list --project=elevatediq-runner --filter="name:runner-ssh-key"'

# 4. Restart watcher if needed
ssh akushnir@192.168.168.42 'sudo systemctl restart wait-and-deploy.service'
```

### Issue: "Permission denied" error in logs

**Symptoms:** Watcher logs show permission errors for credential provider

**Troubleshooting:**
```bash
# For GSM: Check account has Secret Manager Viewer role
gcloud projects get-iam-policy elevatediq-runner \
  --flatten="bindings[].members" \
  --filter="members:kushin77@gmail.com"

# For Vault: Check VAULT_TOKEN is valid
vault auth list

# For AWS: Check IAM permissions for SecretsManager
aws iam get-user
```

### Issue: SSH key authorization failed

**Symptoms:** Deployment fails to connect to worker node

**Troubleshooting:**
```bash
# 1. Verify SSH key exists on bastion
ls -la /opt/app/direct-deploy.sh

# 2. Check public key authorized on worker
ssh akushnir@192.168.168.42 'cat ~/.ssh/authorized_keys | grep -i runner'

# 3. Test SSH connection manually
ssh -i .ssh/runner_ed25519 akushnir@192.168.168.42 'echo SUCCESS'

# 4. Re-authorize key if needed
cat .ssh/runner_ed25519.pub | ssh akushnir@192.168.168.42 \
  'cat >> ~/.ssh/authorized_keys'
```

### Issue: Deployment completes but worker isn't updated

**Symptoms:** Deployment succeeds (no errors) but code isn't deployed

**Troubleshooting:**
```bash
# 1. Check deployment location on worker
ssh akushnir@192.168.168.42 'ls -la /opt/self-hosted-runner/ | head -20'

# 2. Verify git checkout was successful
ssh akushnir@192.168.168.42 'cd /opt/self-hosted-runner && git log --oneline -5'

# 3. Check deployment permissions
ssh akushnir@192.168.168.42 'ls -la /opt/ | grep self-hosted'

# 4. Manually run deployment
bash scripts/direct-deploy.sh gsm main
```

---

## Next Deployments

**After first deployment, the system is fully automatic:**

- Code changes → Commit to main → Automatic deployment (30-second max delay)
- No manual trigger needed
- No CI/CD workflows (disabled by design)
- Direct-deploy-only model enforced

**To trigger manual deployment:**
```bash
# Update code and commit
git add .
git commit -m "deployment: your-change-description"
git push origin main

# Watcher will auto-detect within 30 seconds and deploy
# Monitor via: ssh akushnir@192.168.168.42 'systemctl status wait-and-deploy.service'
```

---

## Quick Reference

### Key Commands

```bash
# Check watcher status
ssh akushnir@192.168.168.42 'systemctl status wait-and-deploy.service'

# View deployment logs
ssh akushnir@192.168.168.42 'sudo journalctl -u wait-and-deploy.service -n 50'

# Check GitHub audit trail
gh issue view 2072 --repo kushin77/self-hosted-runner

# Verify worker node state
ssh akushnir@192.168.168.42 'cd /opt/self-hosted-runner && git log --oneline -3'

# Manually test credential access
ssh akushnir@192.168.168.42 'gcloud secrets list --project=elevatediq-runner'
```

### Important Files

- **Watcher Script:** `/usr/local/bin/wait-and-deploy.sh` (on bastion)
- **Orchestrator:** `/opt/app/direct-deploy.sh` (on worker)
- **SSH Key (Local):** `./ssh/runner_ed25519` (never commit)
- **Audit Trail:** GitHub issue #2072 or `logs/deployment-verification-audit.jsonl`
- **Systemd Unit:** `/etc/systemd/system/wait-and-deploy.service` (on bastion)

### Important Variables

```bash
GCLOUD_PROJECT=elevatediq-runner     # GCP project for GSM
DEPLOY_TARGET=192.168.168.42          # Worker node IP
DEPLOY_USER=akushnir                   # Worker node user
SLEEP_SECONDS=30                       # Polling interval
MAX_ATTEMPTS=360                       # Max polling attempts (3 hours)
```

---

## Deployment Architecture

```
┌─────────────────────────────────────┐
│  Credential Provider                │
│  (GSM | Vault | AWS)                │
│                                     │
│  Contains: SSH private key +user    │
└────────────┬────────────────────────┘
             │ (credentials available)
             ▼
┌─────────────────────────────────────┐
│  Bastion (192.168.168.42)           │
│                                     │
│  wait-and-deploy.sh (systemd)       │
│  • Polling interval: 30s             │
│  • Detects credentials               │
│  • Triggers direct-deploy.sh        │
└────────────┬────────────────────────┘
             │ (credentials detected)
             ▼
┌─────────────────────────────────────┐
│  direct-deploy.sh (orchestrator)    │
│                                     │
│  1. Fetch credentials (ephemeral)   │
│  2. Create git bundle (SHA256)      │
│  3. Transfer via SCP                │
│  4. Checkout on target              │
│  5. Post audit entry                │
│  6. Destroy credentials (trap)      │
└────────────┬────────────────────────┘
             │ (deployment complete)
             ▼
┌─────────────────────────────────────┐
│  Worker: 192.168.168.42             │
│  /opt/self-hosted-runner            │
│  (Latest code deployed)             │
└─────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│  Immutable Audit Trail              │
│  • GitHub issue #2072               │
│  • logs/deployment-audit.jsonl      │
│  (No truncation, permanent)         │
└─────────────────────────────────────┘
```

---

## Summary

### ✅ What's Ready
- All infrastructure deployed and tested
- Watcher actively polling on bastion
- SSH keys generated and ready
- Audit infrastructure operational
- Documentation complete

### ⏳ What's Required (Your Action)
- Provision SSH key to one credential provider (5 minutes)
- Run one command: `bash scripts/deploy-operator-credentials.sh [gsm|vault|aws]`

### 🚀 What Happens Next (Automatic)
- Watcher detects credentials within 30 seconds
- Direct-deploy.sh auto-triggers
- Deployment executes automatically
- Audit entry posted to GitHub
- System ready for next deployment

---

**🎯 Ready to go-live. Awaiting operator credential provisioning.**

**Next Step:** Run the provisioning command for your chosen credential provider.
