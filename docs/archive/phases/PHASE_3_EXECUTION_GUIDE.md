# Phase 3: Key Revocation - Execution Guide

**Status:** Ready for execution after Phase 2 complete

**Issue:** #1948

**Duration:** 1-2 hours (with dry-run validation)

---

## 📋 Overview

Phase 3 replaces and revokes all potentially exposed keys across:
- ✅ Google Cloud Platform (GCP)
- ✅ Amazon Web Services (AWS)
- ✅ HashiCorp Vault

**Two-Stage Process:**
1. **Stage 1 - Dry-Run:** Preview what will be revoked (non-destructive)
2. **Stage 2 - Full Execution:** Actually revoke (after approval)

---

## 🔍 Stage 1: Dry-Run (Safe Preview)

### Execute Dry-Run Workflow

```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run revoke-keys.yml \
  -f dry_run="true" \
  -f perform_revocation="false" \
  --ref main
```

### Monitor Progress
```bash
# View in browser
open "https://github.com/kushin77/self-hosted-runner/actions/workflows/revoke-keys.yml"

# Or check status
gh run list --workflow=revoke-keys.yml --limit=1
```

### What You'll See

Output will show (example):

```
═══════════════════════════════════════════
  DRY-RUN: What Would Be Revoked
═══════════════════════════════════════════

GCP Keys Found:
  • service-account-key-1234 (created 2026-01-15)
  • service-account-key-5678 (created 2026-02-01)
  → Would revoke: 2 keys

AWS Credentials Found:
  • AKIA... (created 2026-01-20)
  • ASIA... (created 2026-02-10)
  → Would revoke: 2 access keys

Vault Secrets Found:
  • database/static/app-user (exp: 2026-03-30)
  • aws/creds/app-role (exp: 2026-04-15)
  → Would rotate: 2 secrets

═══════════════════════════════════════════
TOTAL REVOCATIONS: 6 credentials
═══════════════════════════════════════════
```

### Approval Process

1. **Review the dry-run output**
   - Check what will be revoked
   - Ensure nothing critical is included
   - Verify all items are expected

2. **Get stakeholder approval**
   - Share output with security team
   - Get ops team sign-off
   - Document approvals

---

## ✅ Stage 2: Full Execution (After Approval)

### Execute Full Revocation

```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run revoke-keys.yml \
  -f dry_run="false" \
  -f perform_revocation="true" \
  --ref main
```

### What Happens

**Parallel Revocation (All at once):**
```
GCP Secret Manager:
  ✓ Revoke service account keys
  ✓ Rotate cross-provider keys
  ✓ Log revocation timestamps

AWS Secrets Manager:
  ✓ Rotate access key pairs
  ✓ Disable old keys
  ✓ Log AWS API calls

HashiCorp Vault:
  ✓ Rotate database credentials
  ✓ Revoke lease tokens
  ✓ Create new key material
  ✓ Log rotations to audit

GitHub Secrets:
  ✓ Update all OIDC references
  ✓ Verify new auth methods
  ✓ Test dynamic retrieval
```

### Real-Time Monitoring

```bash
# Watch workflow execute
gh run watch $(gh run list --workflow=revoke-keys.yml --limit=1 --json databaseId -q '.[0].databaseId')

# Or monitor logs
gh run view $(gh run list --workflow=revoke-keys.yml --limit=1 --json databaseId -q '.[0].databaseId') --log
```

---

## 📊 Validation: Post-Revocation Checks

After execution completes:

### Check 1: Verify Revocations in Audit Trail
```bash
# View immutable audit log
cat .key-rotation-audit/key-revocation-audit.jsonl | jq '.[] | {timestamp, action, status}' | tail -10
```

**Expected output:**
```json
{
  "timestamp": "2026-03-08T23:45:32Z",
  "action": "revoke_gcp_keys",
  "status": "success"
}
{
  "timestamp": "2026-03-08T23:46:15Z",
  "action": "revoke_aws_keys",
  "status": "success"
}
{
  "timestamp": "2026-03-08T23:47:02Z",
  "action": "revoke_vault_secrets",
  "status": "success"
}
```

### Check 2: Validate No Secrets in Repository
```bash
# Run git-secrets scan
git secrets --scan

# Expected output:
# ✓ No secrets detected
# ✓ All suspicious patterns cleared
```

### Check 3: Test Dynamic Secret Retrieval
```bash
# Test GCP retrieval
gh workflow run compliance-auto-fixer.yml --ref main

# Monitor to verify it uses new WIF provider
gh run watch $(gh run list --workflow=compliance-auto-fixer.yml --limit=1 --json databaseId -q '.[0].databaseId')
```

### Check 4: Verify GitHub Secrets Updated
```bash
gh secret list --repo kushin77/self-hosted-runner

# Expected: All secrets show rotation timestamps
```

---

## ✨ Success Criteria

Phase 3 is complete when:

- [x] Dry-run executed and reviewed
- [x] Full revocation executed successfully
- [x] No errors in workflow logs
- [x] Audit trail shows all revocations
- [x] git-secrets scan passes
- [x] Dynamic secret retrieval works
- [x] All GitHub secrets updated with new values

---

## 🚨 Rollback Plan (If Needed)

If revocation causes issues:

```bash
# Step 1: Stop workflows
git push origin --delete revoke-keys

# Step 2: Revert to previous commit (before Phase 3)
git log --oneline | grep "Phase 3"
git revert <phase3-commit>

# Step 3: Restore old secrets from secure backup
# (Requires separate restore procedure)

# Step 4: Notify security team
# Document what failed and why
```

---

## 📋 Execution Checklist

### Pre-Execution
- [ ] Phase 2 completed successfully
- [ ] All 4 GitHub secrets exist and have values
- [ ] OIDC/WIF authentication working
- [ ] AWS OIDC provider created
- [ ] Vault JWT endpoint accessible
- [ ] Current backups taken (if applicable)

### Dry-Run Stage
- [ ] Run dry-run workflow
- [ ] Review output
- [ ] Confirm items to be revoked
- [ ] Get stakeholder approval
- [ ] Document dry-run results

### Full Execution Stage
- [ ] Execute full revocation workflow
- [ ] Monitor all steps complete
- [ ] Verify no errors in logs
- [ ] Run post-revocation validation checks
- [ ] Confirm audit trail populated

### Validation Stage
- [ ] Audit trail shows revocations
- [ ] git-secrets passes
- [ ] Dynamic retrieval works
- [ ] GitHub secrets updated
- [ ] No service interruptions

### Completion
- [ ] Close Issue #1948
- [ ] Document what was revoked
- [ ] Proceed to Phase 4

---

## 🎯 Next Steps After Phase 3

After Phase 3 completion:

**Phase 4: Production Validation**
- Automated daily execution
- Monitor for 1-2 weeks
- Verify zero failures
- Collect metrics

See: `PHASE_4_EXECUTION_GUIDE.md`

---

## 📞 Support

**Common Issues:**

**Issue: Dry-run shows no credentials to revoke**
- Cause: Repository is already clean
- Solution: This is OK - proceed to Phase 4

**Issue: Full execution fails on GCP step**
- Cause: Service account permissions
- Solution: Verify service account has Editor role

**Issue: git-secrets scan fails after revocation**
- Cause: Old key material still in git history
- Solution: Run `git secrets --install` and rescan

**Issue: Dynamic retrieval fails after revocation**
- Cause: New credentials not properly updated
- Solution: Re-run Phase 2 to refresh secrets

---

**Status: Phase 3 Ready for Execution**

Command to run (after Phase 2 complete):
```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run revoke-keys.yml \
  -f dry_run="true" \
  -f perform_revocation="false" \
  --ref main
```
