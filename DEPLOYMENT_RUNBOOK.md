# 🚀 Self-Healing Infrastructure Deployment Runbook
**Date**: March 8, 2026  
**Status**: ✅ Ready for Production Deployment  
**Timeline**: All approvals granted, proceed immediately  

---

## Executive Summary

Complete self-healing infrastructure implementation is ready for production deployment. This runbook guides the 5-phase deployment with zero waiting:

1. **Phase 1**: Merge PR #1924 (multi-layer orchestration)
2. **Phase 2**: Enable OIDC/WIF (GCP, AWS, Vault)
3. **Phase 3**: Rotate/revoke exposed keys
4. **Phase 4**: Deploy production workflows
5. **Phase 5**: Monitor first week + escalation

---

## Phase 1: Merge PR #1924 (0-5 minutes)

### Step 1.1: Review & Merge
```bash
# Show PR details
gh pr view 1924 --json title,state,approvals

# Merge to main (squash-merge recommended)
gh pr merge 1924 --squash --auto

# Verify merge
gh pr view 1924 --json mergeCommit
```

**Expected Output**: PR merged, workflows auto-deploy to `main` branch

### Step 1.2: Verify Workflow Definitions
```bash
# Confirm workflows are now active in main
gh workflow list

# Expected workflows:
#  1. compliance-auto-fixer.yml (00:00 UTC daily)
#  2. rotate-secrets.yml (03:00 UTC daily)
#  3. self-healing-orchestrator.yml (every 6h)
#  4. setup-oidc-infrastructure.yml (manual trigger)
#  5. revoke-keys.yml (manual trigger)
```

**Timeline**: ~5 minutes

---

## Phase 2: Enable OIDC/WIF (5-30 minutes)

### Step 2.1: Update GitHub Secrets

Populate these repository secrets (no long-lived keys):

```bash
# GCP (from setup-oidc-infrastructure workflow output)
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/PROJECT_ID/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID"
gh secret set GCP_SERVICE_ACCOUNT --body "ci-bootstrap@PROJECT_ID.iam.gserviceaccount.com"
gh secret set GCP_PROJECT_ID --body "YOUR_GCP_PROJECT_ID"

# AWS (from setup-oidc-infrastructure workflow output)
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::ACCOUNT_ID:role/github-actions-role"
gh secret set AWS_ACCOUNT_ID --body "YOUR_AWS_ACCOUNT_ID"

# Vault (manual setup)
gh secret set VAULT_ADDR --body "https://vault.example.com"
gh secret set VAULT_TOKEN --body "s.VAULT_TOKEN_HERE"  # Temporary setup token only
```

**Security**: Remove `VAULT_TOKEN` after setup completes (Step 2.3)

### Step 2.2: Trigger Setup Workflow

```bash
# Run automated OIDC/WIF setup (idempotent, safe to retry)
gh workflow run setup-oidc-infrastructure.yml \
  -f setup_gcp=true \
  -f setup_aws=true \
  -f setup_vault=true

# Monitor setup run
gh run list --workflow=setup-oidc-infrastructure.yml --limit=1

# View artifacts/logs
gh run view RUN_ID --log
```

**Expected Duration**: ~15 minutes

**Completion Criteria**:
- ✅ GCP Workload Identity Provider created
- ✅ AWS OIDC provider registered + IAM role created
- ✅ Vault JWT auth configured
- ✅ All provider secrets populated in GitHub

### Step 2.3: Revoke Temporary Vault Token

```bash
# After setup completes, revoke temporary setup token
vault token revoke --self  # (or from Vault UI)

# Delete temporary secret
gh secret delete VAULT_TOKEN

# Later: When rotation workflow runs, it will fetch new token via OIDC
```

**Timeline**: ~25 minutes

---

## Phase 3: Rotate/Revoke Exposed Keys (30-45 minutes)

### Step 3.1: Prepare Key Inventory

Identify all exposed keys by reviewing:
- Removed commits in git history
- GitHub Security → Secret scanning
- Issue #1910 (GCP key issue)
- Issue #1911 (all secret layers unhealthy)

Set environment variables:
```bash
export EXPOSED_GCP_SA_EMAIL="ci-user@project.iam.gserviceaccount.com"  # Compromised SA
export EXPOSED_AWS_KEY_IDS="AKIAIOSFODNN7EXAMPLE,AKIAJ7EXAMPLE"  # Comma-separated
export EXPOSED_VAULT_ROLE_IDS="github-actions-old,ci-legacy"  # Comma-separated
```

### Step 3.2: Run Key Revocation (Dry-Run First)

```bash
# DRY-RUN (audit only, no actual revocations)
gh workflow run revoke-keys.yml \
  -f revoke_gcp=true \
  -f revoke_aws=true \
  -f revoke_vault=true \
  -f dry_run=true

# Monitor
gh run list --workflow=revoke-keys.yml --limit=1

# Review artifact (no actual deletions in dry-run)
gh run view RUN_ID --json artifacts
```

**Expected Duration**: ~5 minutes (no actual revocations)

### Step 3.3: Execute Actual Revocation

Once dry-run succeeds and you've reviewed the audit:

```bash
# REAL EXECUTION (actual key revocations)
gh workflow run revoke-keys.yml \
  -f revoke_gcp=true \
  -f revoke_aws=true \
  -f revoke_vault=true \
  -f dry_run=false

# Monitor
gh run list --workflow=revoke-keys.yml --limit=1

# Verify no secrets remain
gh run view RUN_ID --log | grep -i "secret\|pass\|key"

# Check immutable audit trail
gh run view RUN_ID --json artifacts
```

**Expected Duration**: ~10 minutes

### Step 3.4: Create New Keys

For each provider, create new minimal-privilege keys:

**GCP**:
```bash
# Create new bootstrap SA key
gcloud iam service-accounts keys create key.json \
  --iam-account=ci-bootstrap@PROJECT_ID.iam.gserviceaccount.com

# Store in GSM only (not in repo)
gcloud secrets create gcp-sa-key --data-file=key.json --project=PROJECT_ID
rm -f key.json  # Ephemeral cleanup
```

**AWS**: 
- IAM role already created
- Access keys auto-managed via OIDC (use assume role, not long-lived keys)

**Vault**:
- Already OIDC-authenticated; no new AppRole keys needed

**Timeline**: ~15 minutes

---

## Phase 4: Deploy Production Workflows (45-60 minutes)

### Step 4.1: Validate Scheduled Workflows

All workflows are now scheduled in `main`. No additional deployment needed.

Verify activation:
```bash
# Show scheduled workflow runs
gh workflow list

# Expected schedules:
# ✓ compliance-auto-fixer.yml:      00:00 UTC daily
# ✓ rotate-secrets.yml:              03:00 UTC daily
# ✓ self-healing-orchestrator.yml:   Every 6 hours
```

### Step 4.2: Dry-Run All Workflows

```bash
# Test Compliance Auto-Fixer (dry-run mode is default)
gh workflow run compliance-auto-fixer.yml -f mode=dry-run

# Test Secrets Rotation (with dry-run)
gh workflow run rotate-secrets.yml -f dry-run=true

# Test Orchestrator
gh workflow run self-healing-orchestrator.yml
```

Monitor all three:
```bash
# Watch runs
watch -n 5 'gh run list --workflow=compliance-auto-fixer.yml --limit=3'
watch -n 5 'gh run list --workflow=rotate-secrets.yml --limit=3'
watch -n 5 'gh run list --workflow=self-healing-orchestrator.yml --limit=3'

# Check artifacts
gh run view RUN_ID --json artifacts
```

**Expected Outputs**:
- ✅ Immutable audit trails (`.compliance-audit/*.jsonl`, `.credentials-audit/*.jsonl`)
- ✅ Metrics (`.self-healing-metrics/*.json`)
- ✅ No secrets exposed in logs or artifacts
- ✅ All operations idempotent

### Step 4.3: Create Monitoring Dashboard

```bash
# Create issues for daily monitoring (see Phase 5 below)
# Manually check artifact uploads and metrics daily for first week
```

**Timeline**: ~15 minutes

---

## Phase 5: Monitor & Escalation (Week 1 + ongoing)

### Step 5.1: Daily Monitoring (First 7 Days)

Create daily report issue:
```bash
gh issue create \
  --title "📊 Daily Self-Healing Monitoring Report - Week 1 (3/8 - 3/14/2026)" \
  --body "Track all automated workflow runs and report any failures or anomalies.

Daily checklist:
- [ ] Mon 3/8: Compliance fixer (00:00), Rotation (03:00), Orchestrator (00:00, 06:00, 12:00, 18:00)
- [ ] Tue 3/9: (same schedule)
- [ ] Wed 3/10: (same schedule)
- [ ] Thu 3/11: (same schedule)
- [ ] Fri 3/12: (same schedule)
- [ ] Sat 3/13: (same schedule)
- [ ] Sun 3/14: (same schedule + End of week summary)

For each run, verify:
✓ Audit artifacts uploaded
✓ No secrets in logs
✓ All operations completed (even if some failed)
✓ Metrics logged

If failures >3/day, create ESCALATION issue immediately." \
  --assignee kushin77 \
  --label monitoring,ops
```

### Step 5.2: Check Artifact Uploads

```bash
# List recent runs and their artifacts (daily)
gh run list \
  --workflow=compliance-auto-fixer.yml \
  --workflow=rotate-secrets.yml \
  --workflow=self-healing-orchestrator.yml \
  --limit=21  # 7 days × 3 workflows (approximate)

# Download audit trail
gh run view RUN_ID --json artifacts

# Verify audit content
jq '.' .compliance-audit/compliance-fixes-*.jsonl | head -20
jq '.' .credentials-audit/rotation-audit.jsonl | head -20
jq '.' .self-healing-metrics/workflow-metrics-*.json | head -20
```

### Step 5.3: Create Escalation Issues

If any critical failures occur:

```bash
# Escalate immediately
gh issue create \
  --title "🚨 Self-Healing Workflow Failure - Requires Investigation" \
  --body "Workflow XXX failed at YYYY UTC. Details:
  
Run: ${{ github.server_url }}/${{ github.repository }}/actions/runs/RUN_ID

Immediate actions:
1. Review workflow logs
2. Check credential provider health
3. Post findings to monitoring issue

Impact: Compliance fixes and rotations may be delayed." \
  --label incident,self-healing \
  --assignee kushin77
```

### Step 5.4: Post Week-1 Summary

After 7 days:

```bash
# Post summary to monitoring issue
gh issue comment MONITORING_ISSUE_ID --body "## Week 1 Summary (3/8 - 3/14/2026)

**Compliance Fixer**:
- ✓ 7 runs completed (00:00 UTC daily)
- ✓ N violations detected
- ✓ M fixes applied
- ✓ Audit trail complete

**Secrets Rotation**:
- ✓ 7 runs completed (03:00 UTC daily)
- ✓ GSM: N rotations
- ✓ Vault: N rotations
- ✓ AWS: N rotations
- ✓ Audit trail complete

**Orchestrator**:
- ✓ 42 runs completed (every 6h)
- ✓ Health checks: All green
- ✓ Escalations: 0

**Assessment**: ✅ Production ready, all systems nominal

**Actions for Week 2**:
- Continue daily monitoring
- Integrate with existing retry/auto-merge (see #1913)
- Consider ChatOps commands for manual overrides"
```

---

## Success Criteria Checklist

- [ ] **Phase 1**: PR #1924 merged, workflows deployed
- [ ] **Phase 2**: OIDC/WIF configured, all secrets populated
- [ ] **Phase 3**: Exposed keys revoked, no secrets remain, new keys created
- [ ] **Phase 4**: All dry-runs pass, audit artifacts verified
- [ ] **Phase 5**: Week 1 monitoring clean, escalation process validated

---

## Rollback Procedure (If Needed)

If any phase fails critically:

```bash
# Stop scheduled workflows
gh workflow disable compliance-auto-fixer.yml
gh workflow disable rotate-secrets.yml
gh workflow disable self-healing-orchestrator.yml

# Revert to previous commit
git revert HEAD

# Restore long-lived keys temporarily (from secure backup)
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$(cat gcp-key.json)"

# Re-enable for debugging
gh workflow enable <workflow-name>
```

---

## Architecture Overview

```
GitHub Actions (Scheduled)
  ├─ 00:00 UTC: compliance-auto-fixer.yml
  │  └─ PyYAML scanner → idempotent audit trail
  │
  ├─ 03:00 UTC: rotate-secrets.yml
  │  ├─ GCP (OIDC/WIF)
  │  ├─ Vault (JWT)
  │  └─ AWS (OIDC)
  │
  └─ Every 6h: self-healing-orchestrator.yml
     ├─ Health check (all layers)
     ├─ State recovery
     ├─ Auto-remediate
     └─ Escalation + metrics

All components:
✓ Immutable (audit trails committed to repo)
✓ Ephemeral (no secrets stored at rest)
✓ Idempotent (safe to re-run)
✓ No-ops (fully automated)
✓ GSM/Vault/KMS (dynamic retrieval)
```

---

## Key Resources

| Tool | Purpose | Config |
|------|---------|--------|
| GCP WIF | OIDC auth provider | `.github/workflows/setup-oidc-infrastructure.yml` |
| AWS IAM Role | OIDC federated role | Auto-created by setup workflow |
| Vault JWT | Secret auth method | Auto-configured by setup workflow |
| GSM | Credential storage | Referenced in `rotate-secrets.yml` |
| Vault | Credential storage | Referenced in `rotate-secrets.yml` |
| AWS Secrets Mgr | Credential storage | Referenced in `rotate-secrets.yml` |

---

## Post-Deployment Enhancements

After Week 1 validation (Phase 5 complete):

1. **Integrate orchestrator** into existing modules (#1913):
   - Wire retry engine, auto-merge, predictive healing
   - Credential injection for all

2. **Add observability**:
   - Set up dashboards for audit trail analysis
   - Real-time alerting on failures

3. **Enable escalation**:
   - Slack/email notifications on failures
   - PagerDuty integration for on-call

4. **Production Gate** (Week 2):
   - Full integration validation
   - Load testing (concurrent rotations)
   - Chaos engineering (provider outages)

---

## Support & Escalation

**For questions about the runbook**:
- Open issue: `support: self-healing-deployment`

**For production incidents**:
- Create issue: `incident: <workflow-name>-failure`
- Assign to: `kushin77`
- Label: `critical,incident`

**For feature requests**:
- Create issue: `enhancement: self-healing-<feature>`

---

**Document Created**: March 8, 2026  
**Status**: ✅ Ready for deployment  
**Approval**: All requirements met, proceed immediately  

---

## Quick Start Commands

```bash
# 1. Merge PR
gh pr merge 1924 --squash

# 2. Set secrets (replace with actual values)
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "..."
gh secret set GCP_SERVICE_ACCOUNT --body "..."
gh secret set AWS_ROLE_TO_ASSUME --body "..."
gh secret set VAULT_ADDR --body "..."

# 3. Run setup
gh workflow run setup-oidc-infrastructure.yml

# 4. Dry-run revocation
gh workflow run revoke-keys.yml -f dry_run=true

# 5. Run actual revocation
gh workflow run revoke-keys.yml -f dry_run=false

# 6. Test production workflows
gh workflow run compliance-auto-fixer.yml -f mode=dry-run
gh workflow run rotate-secrets.yml -f dry_run=true
gh workflow run self-healing-orchestrator.yml

# 7. Monitor (daily for 7 days)
gh run list --limit=50
gh run view RUN_ID --json artifacts
```

---

**End of Deployment Runbook**
