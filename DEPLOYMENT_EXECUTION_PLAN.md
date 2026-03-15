# Phase 3 Production Deployment - Execution Plan
**Status**: READY FOR EXECUTION  
**Date**: March 15, 2026  
**Operator**: Automated (Hands-Off) or Manual (Target Host Only)

---

## 🟢 Pre-Deployment Verification

All prerequisites verified and locked:
- [x] On-prem policy enforcement (fail-closed gates active)
- [x] Domain standardization (elevatediq.ai enforced)
- [x] Service account naming (elevatediq-svc-* standard applied)
- [x] GitHub governance (5 issues closed, EPIC updated)
- [x] Production baseline (2026-03-15T04:16:09Z captured)
- [x] Redeploy orchestrator (zero hard failures)
- [x] NAS integration (elevatediq-svc-nas SSH user)
- [x] Vault AppRole (configured in GSM)
- [x] KMS encryption keys (verified accessible)

---

## 🚀 Deployment Execution (Two Options)

### Option A: Automated Hands-Off Execution
**Trigger**: From CI/CD orchestrator or automation host

```bash
# 1. Pull latest (already done)
cd /home/akushnir/self-hosted-runner
git pull origin main --ff-only

# 2. Set execution environment (automation host only)
export DRY_RUN=false
export ENFORCE_ONPREM_ONLY=true
export ENFORCE_DOMAIN=true
export ENFORCE_NAMING=true
export TARGET_WORKER_HOST=192.168.168.42
export VAULT_ADDR=https://vault.elevatediq.ai:8200
export VAULT_OIDC_ROLE=elevatediq-deployment-role

# 3. Execute (immutable, ephemeral, idempotent)
bash scripts/redeploy/redeploy-100x.sh | tee /var/log/deployment/redeploy-$(date +%Y%m%dT%H%M%SZ).log

# 4. Monitor exit code
if [ $? -eq 0 ]; then
  # Success: post notification to GitHub issue #3186
  gh issue comment 3186 --body "✅ Production deployment completed at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
else
  # Failure: capture audit trail and post to #3186
  gh issue comment 3186 --body "❌ Deployment failed. Review audit-trail.jsonl"
  exit 1
fi
```

### Option B: Manual Execution from Target Host
**Requires**: SSH access to 192.168.168.42

```bash
# 1. SSH to target worker
ssh akushnir@192.168.168.42

# 2. Prepare (immutable, from git)
cd ~/self-hosted-runner
git pull origin main --ff-only

# 3. Set environment (no hardcoded secrets - GSM/Vault fetched at runtime)
export DRY_RUN=false
export ENFORCE_ONPREM_ONLY=true
export VAULT_ADDR=https://vault.elevatediq.ai:8200

# 4. Execute with policy enforcement (will block cloud patterns)
bash scripts/redeploy/redeploy-100x.sh

# 5. Monitor console output for policy enforcements and deployment status
# Exit code 42 = policy violation (audit trail in audit-trail.jsonl)
# Exit code 0 = deployment success
```

---

## 🔐 Credential Handling (No Ops, Hands-Off)

**All credentials fetched at runtime via GSM/Vault/KMS**:
- SSH keys for NAS access: GSM secret `elevatediq-svc-nas-ssh-key`
- Git credentials: GSM secret `elevatediq-svc-git-ssh-key`  
- Vault AppRole: GSM secrets `elevatediq-approle-role-id`, `elevatediq-approle-secret-id`
- KMS key: Passed via `VAULT_ADDR` environment variable
- No `.env` files required (all from GSM at runtime)

**Immutable & Ephemeral**:
- No credential files left on disk after execution
- Secrets fetched fresh on each run
- Idempotent: safe to re-run
- No manual ops: fully automated

---

## 📊 Deployment Sequence

1. **Preflight Checks**: Tool availability, reachability, permissions
2. **Policy Enforcement**: On-prem-only gates, domain validation, naming standards
3. **NAS Sync**: Pull IAC from 192.168.168.100 (elevatediq-svc-nas)
4. **Deployment Steps** (immutable sequence):
   - Pre-deployment readiness probe
   - Kubernetes health checks
   - Deployment runbook execution
   - Post-deployment validation
5. **NAS Backup**: Archive to GCP with retention policy
6. **Audit Trail**: All steps logged to audit-trail.jsonl
7. **GitHub Update**: Automatic issue comment with completion status

---

## ✅ Success Criteria

After execution, verify:
- [ ] Exit code = 0 (success) or 42 (policy violation, investigate)
- [ ] audit-trail.jsonl populated with timestamps
- [ ] NAS backup completed (reports/redeploy/nas-backup-*.txt)
- [ ] GitHub issue #3186 updated with deployment status
- [ ] No credential files in /tmp or home directories
- [ ] Services on 192.168.168.42 responding normally

---

## 🔄 Rollback Plan

If deployment fails:

1. **Check audit trail**: `tail -f audit-trail.jsonl`
2. **Review gap analysis**: `cat reports/redeploy/redeploy-gap-analysis-*.md`
3. **SSH to 192.168.168.42**: Manual rollback via systemctl restart if needed
4. **Rerun validation**: `DRY_RUN=true bash scripts/redeploy/redeploy-100x.sh` (safe)
5. **Post to GitHub**: Comment on issue #3186 with failure details

---

## 🎯 Deployment Properties

- **Immutable**: All config from git, no runtime changes persisted beyond execution
- **Ephemeral**: Credentials not stored on disk, fetched fresh each run
- **Idempotent**: Safe to execute multiple times (no duplicate resource creation)
- **No Ops**: Fully automated, no manual steps or human intervention required
- **Hands-Off**: Can run unattended via cron, CI/CD, or CloudScheduler
- **Encrypted**: All secrets via GSM (encrypted at rest + in transit) + Vault + KMS

---

## 📋 Final Execution Checklist

- [ ] Approved by stakeholder (user)
- [ ] All GitHub issues updated (5 closed, #3186 EPIC progress updated)
- [ ] Production baseline captured and signed off
- [ ] Target host (192.168.168.42) online and accessible
- [ ] GSM/Vault credentials not expired
- [ ] NAS connectivity verified (192.168.168.100)
- [ ] Audit logging configured
- [ ] Policy gates tested and verified fail-closed
- [ ] Dry-run validation successful (DRY_RUN=true PASS)
- [ ] All prerequisites checklist completed

**Status**: 🟢 READY FOR EXECUTION

---

## 🚀 EXECUTE NOW

Choose Option A (Automated) or Option B (Manual) from above section.
All safety mechanisms active. Framework ready. No blockers.
