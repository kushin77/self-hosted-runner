# Production Activation Checklist

**Date:** 2026-03-09  
**Status:** ✅ READY FOR ACTIVATION  
**Last Updated:** 2026-03-09 13:14 UTC

## Pre-Activation (Repository Ready)

All of these are ✅ COMPLETE:

- [x] Direct deployment scripts (`scripts/direct-deploy.sh`) — hardened with GSM/Vault/KMS support
- [x] Watcher script (`scripts/wait-and-deploy.sh`) — polls for credential availability
- [x] Systemd unit template (`infra/wait-and-deploy.service`) — for watcher deployment
- [x] GitHub Actions workflows — all archived to `.github/workflows/.disabled/`
- [x] Dependabot — archived to `.github/.disabled/dependabot.yml`
- [x] Audit infrastructure — GitHub issue comments (#2072) + immutable JSONL logs
- [x] Documentation — `OPERATOR_RUNBOOK.md`, `CONTRIBUTING.md`, `DIRECT_DEVELOPMENT_POLICY.md`
- [x] Portal defaults — updated to `192.168.168.42` in `src/api/socket.ts`, `apps/portal/web/index.html`
- [x] All changes committed to `main` and pushed to repository

## Required Operator Actions (Before First Deployment)

These require operator access to `192.168.168.42`:

### 1. SSH Access Setup
```bash
# Verify SSH access to worker node
ssh -i ~/.ssh/deploy-key deploy@192.168.168.42 "echo ✅ SSH working"

# Expected: success response from 192.168.168.42
```

### 2. Credentials Provisioning
Ensure credentials are available in one of:
- **Google Secret Manager (GSM):** `gcloud secrets versions access latest --secret "deploy-credentials"`
- **HashiCorp Vault:** `vault kv get secret/deploy-credentials`
- **AWS Secrets Manager:** `aws secretsmanager get-secret-value --secret-id deploy-credentials`

```bash
# Example: Verify GSM access
gcloud secrets versions access latest --secret "deploy-credentials" > /tmp/creds.json
```

### 3. Deploy Watcher (Ops Bastion)

Transfer and enable the watcher on the Ops bastion:

```bash
# Copy watcher script
scp scripts/wait-and-deploy.sh ops-bastion:/usr/local/bin/
chmod +x /usr/local/bin/wait-and-deploy.sh

# Copy systemd unit
scp infra/wait-and-deploy.service ops-bastion:/etc/systemd/system/
systemctl daemon-reload

# Enable and start watcher
systemctl enable --now wait-and-deploy.service
systemctl status wait-and-deploy.service
```

### 4. GitHub CLI Auth (Optional but Recommended)

For audit posting to GitHub issue #2072:

```bash
# On bastion or deployment host
gh auth login --scopes "repo" --hostname github.com
# Verify: gh issue view 2072 --repo kushin77/self-hosted-runner
```

### 5. First Test Deployment

```bash
# SSH to worker node
ssh deploy@192.168.168.42

# Run a test deployment
/opt/app/direct-deploy.sh --dry-run

# Monitor audit trail
tail -f logs/deployment-verification-audit.jsonl

# Check GitHub issue #2072 for audit comment
```

## Operational Model

### Single Deployment Method
```
Credential Provisioning (GSM/Vault/KMS)
    ↓
wait-and-deploy.sh detects credentials
    ↓
Triggers direct-deploy.sh
    ↓
Script fetches creds → builds bundle → deploys to 192.168.168.42
    ↓
Posts audit to GitHub issue #2072
    ↓
Cleans up ephemeral creds and temp files
```

### Audit Trail
- **Primary:** GitHub issue #2072 (comments)
- **Fallback:** `logs/deployment-verification-audit.jsonl` (immutable JSONL)
- **Optional:** Forward to MinIO via `scripts/forward-audit-to-minio.sh`

### Guarantees
- **Immutable:** No data loss; complete audit history preserved
- **Ephemeral:** No credentials stored; all temps cleaned
- **Idempotent:** Safe to re-run; lock-based state management
- **Hands-off:** No human intervention after initial setup

## Verification Steps

After applying this activation checklist, verify:

```bash
# Check repository state
git log --oneline -5  # Should show recent ops commits

# Verify scripts are executable
ls -la scripts/direct-deploy.sh scripts/wait-and-deploy.sh

# Verify audit infrastructure
tail -5 logs/deployment-verification-audit.jsonl

# Verify portal defaults
grep "192.168.168.42" src/api/socket.ts apps/portal/web/index.html

# Verify workflows are archived
ls -la .github/workflows/.disabled/
test ! -f .github/workflows/auto-provision-fields.yml && echo "✅ Workflows archived"

# Verify Dependabot disabled
test ! -f .github/dependabot.yml && echo "✅ Dependabot archived"
```

## Support & Issues

- **GitHub Issue #2077:** Operational model tracking
- **GitHub Issue #2072:** Audit trail and status updates
- **Runbook:** See `OPERATOR_RUNBOOK.md` for detailed procedures
- **Policy:** See `CONTRIBUTING.md` for deployment authorization

---

**Status:** Ready for production activation. Proceed to operator actions when infrastructure access is available.

🚀 **PRODUCTION READY**
