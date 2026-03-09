# EMERGENCY ROLLBACK PLAN - Multi-Phase Automation

**Document Type:** Disaster Recovery / Emergency Procedures  
**Severity:** CRITICAL  
**Activation:** When Phase 2, 3, 4, or 5 experiences critical failure

---

## Quick Reference - Emergency Stop (60 SECONDS)

```bash
#!/bin/bash
# EXECUTE THIS FIRST IN ANY EMERGENCY

set -e

echo "🚨 EMERGENCY STOP INITIATED"

# 1. Stop all running workflows (< 30 seconds)
gh run cancel-all --workflow "phase-*.yml" 2>/dev/null || true

# 2. Disable auto-triggering (< 20 seconds)
# (Workflows won't re-trigger until manually re-enabled)

# 3. Restore previous credentials (< 10 seconds)
if [ -f "./.credential-backup-latest" ]; then
    source ./.credential-backup-latest
    echo "✅ Previous credentials restored"
fi

echo "🛑 EMERGENCY STOP COMPLETE - SYSTEM IN SAFE STATE"
echo "🔗 Next: Notify escalation contacts"
echo "📋 Next: Review relevant audit logs"
echo "🔄 Next: Execute Phase-Specific Rollback (see below)"
```

---

## Emergency Contact Tree

**Primary Escalation:** _____________________ (Name/Phone)  
**Secondary Escalation:** _____________________ (Name/Phone)  
**Backup Escalation:** _____________________ (Name/Phone)  
**Infrastructure Lead:** _____________________ (Name/Phone)  
**Security Lead:** _____________________ (Name/Phone)  
**CTO/Director:** _____________________ (Name/Phone)

**Call Order:** Primary → Secondary → Backup → All Hands Meeting

---

## Phase-by-Phase Rollback Procedures

### Phase 2 Failure: OIDC/WIF Setup

**Symptoms:**
- Workflow fails during provider registration
- GitHub Actions can't authenticate to GCP/AWS/Vault
- OIDC setup logs show provider errors
- Secrets don't work in workflows

**Immediate Actions (< 5 minutes):**

1. **Stop the workflow:**
   ```bash
   gh run cancel --workflow phase-2-oidc-wif-setup.yml
   ```

2. **Preserve logs for analysis:**
   ```bash
   # Save workflow run details
   gh run view --json log > .rollback-audit/phase-2-failure-$(date +%s).json
   ```

3. **Reset to pre-Phase 2 state:**
   ```bash
   # Delete created GitHub Secrets (they'll be recreated in cleanup)
   for secret in GCP_WIF_PROVIDER_ID AWS_ROLE_ARN VAULT_ADDR VAULT_JWT_ROLE; do
       gh secret delete "$secret" 2>/dev/null || true
   done
   echo "✅ GitHub Secrets cleared"
   ```

4. **Revert any cloud provider changes:**
   ```bash
   # GCP: Delete OIDC provider (if created)
   # gcloud iam workload-identity-pools providers delete \
   #   --location=global --workload-identity-pool=github-pool \
   #   github-oidc 2>/dev/null || true
   
   # AWS: Delete IAM role (if created)
   # aws iam delete-role-policy --role-name github-actions-role \
   #   --policy-name github-actions-policy 2>/dev/null || true
   # aws iam delete-role --role-name github-actions-role 2>/dev/null || true
   
   # Vault: Disable JWT auth (if enabled)
   # VAULT_ADDR=https://vault.example.com vault auth disable jwt 2>/dev/null || true
   
   echo "✅ Cloud provider changes reverted"
   ```

**Diagnosis (Next 30 minutes):**

```bash
# Review OIDC setup audit logs
tail -100 .oidc-setup-audit/oidc_setup.jsonl | jq .

# Check GitHub Actions logs
gh run view <RUN_ID> --json log

# Verify cloud providers didn't partially create resources
# - Check GCP console for dangling WIF providers
# - Check AWS console for dangling IAM roles
# - Check Vault for dangling auth methods
```

**Recovery Path:**

Option A: **Retry Phase 2** (if transient error)
```bash
# Fix root cause (e.g., GCP project permissions, AWS region config)
# Then trigger Phase 2 again
python3 orchestrator.py --trigger-phase-2 \
  --gcp-project-id "YOUR_GCP_PROJECT" \
  --aws-account-id "YOUR_AWS_ACCOUNT" \
  --vault-address "https://vault.example.com"
```

Option B: **Partial OIDC Setup** (if only one cloud provider needed)
```bash
# Manually configure only GCP OIDC:
bash scripts/credentials/setup_gcp_oidc.sh

# Or only AWS:
bash scripts/credentials/setup_aws_wif.sh

# Or only Vault:
bash scripts/credentials/setup_vault_jwt_auth.sh

# Then manually create corresponding GitHub Secrets
gh secret set GCP_WIF_PROVIDER_ID --body "..."
```

Option C: **Skip to Phase 5** (use static credentials temporarily)
```bash
# Fall back to previous static credential mode
# Set all credential backends to stub mode
bash scripts/credentials/disable_all_ephemeral.sh

# Phase 3-5 can still run with static credentials
# (Not recommended for production - temporary only)
```

---

### Phase 3 Failure: Key Revocation

**Symptoms:**
- Revocation workflow fails partway through
- Some credentials revoked, some still valid
- Services experiencing intermittent failures
- Revocation audit shows partial success

**Immediate Actions (< 5 minutes):**

1. **Stop the workflow:**
   ```bash
   gh run cancel --workflow phase-3-revoke-exposed-keys.yml
   ```

2. **Check what was revoked:**
   ```bash
   # Review .revocation-audit/ to see which credentials were already revoked
   jq '.credential_id' .revocation-audit/revocation.jsonl | sort | uniq
   ```

3. **Restore unrevoked credentials:**
   ```bash
   # Services should already be using Phase 2 WIF/JWT tokens
   # No manual action needed - fallback is automatic
   
   # Verify services are healthy on Phase 2 credentials
   for service in $(cat services.txt); do
       curl -s https://$service/health && echo "✅ $service healthy" || echo "❌ $service DOWN"
   done
   ```

4. **Partially resume revocation:**
   ```bash
   # If Phase 3 can be paused/resumed, continue from last checkpoint:
   bash scripts/credentials/revoke_exposed_keys.sh --resume
   
   # Or manually revoke remaining credentials:
   for cred in $(cat remaining-exposed-credentials.txt); do
       echo "Revoking $cred..."
       python3 scripts/credentials/revoke_credential.py "$cred"
   done
   ```

**Diagnosis (Next 30 minutes):**

```bash
# Count successful vs failed revocations
echo "Revoked:"
jq 'select(.status=="revoked") | .credential_id' .revocation-audit/revocation.jsonl | wc -l

echo "Failed:"
jq 'select(.status=="failed") | .credential_id' .revocation-audit/revocation.jsonl | wc -l

# Check service logs for errors
kubectl logs -f deployment/service-name
# or
tail -f /var/log/service.log
```

**Recovery Path:**

Option A: **Complete revocation** (over extended period)
```bash
# Extend revocation window from 15 min to 1-2 hours
# Revoke remaining credentials more slowly
for cred in $(cat remaining-exposed-credentials.txt); do
    python3 scripts/credentials/revoke_credential.py "$cred"
    sleep 300  # 5-minute delay between revocations
    # Check service health after each revocation
done
```

Option B: **Keep temporarily revoked** (investigate failures)
```bash
# Leave already-revoked credentials revoked
# Investigate why remaining revocations failed:
# - Credential backend unreachable?
# - Permission denied?
# - Timeout?

# Fix root cause, then manually revoke remaining
```

Option C: **Restore all exposed credentials** (if critical failure)
```bash
# In extreme emergency, restore revoked credentials:
bash scripts/credentials/restore_revoked_credentials.sh

# (This is NOT recommended - credentials are exposed)
# Only use if service is completely down and revocation broke it

# Then provide manual rotation schedule ASAP
```

---

### Phase 4 Failure: Production Validation

**Symptoms:**
- Validation workflow fails hourly checks
- Health check detects credential access errors
- Audit shows failed credential retrievals
- Validation waits forever (14 days) without passing

**Immediate Actions (< 5 minutes):**

1. **Don't stop the workflow** (Phase 4 is non-blocking)
   ```bash
   # Phase 4 uses workflow_run trigger, doesn't block Phase 5
   # Can continue investigating without stopping Phase 4
   ```

2. **Diagnose the failing health check:**
   ```bash
   # Review validation audit logs
   tail -50 .validation-audit/validation.jsonl | jq '.error'
   
   # Check which system is failing
   tail -50 .validation-audit/validation.jsonl | jq '.system'
   ```

3. **Manually test credential retrieval:**
   ```bash
   # Test GSM access
   bash scripts/credentials/test_gsm_access.sh
   
   # Test Vault access
   bash scripts/credentials/test_vault_access.sh
   
   # Test KMS access
   bash scripts/credentials/test_kms_access.sh
   ```

4. **Fix the underlying issue:**
   ```bash
   # If GCP unreachable: Check GCP API access, network connectivity
   # If Vault unreachable: Check Vault service status, network connectivity
   # If KMS unreachable: Check AWS KMS service status, IAM permissions
   
   # Examples:
   # - Restart the unreachable service
   # - Fix network connectivity
   # - Fix IAM/authentication issue
   # - Increase service quotas if rate-limited
   ```

**Diagnosis (Next 30 minutes):**

```bash
# Get detailed error context
jq '.error, .timestamp, .system' .validation-audit/validation.jsonl | head -20

# Count success vs failures
echo "Successful checks:"
jq 'select(.status=="passed")' .validation-audit/validation.jsonl | wc -l

echo "Failed checks:"
jq 'select(.status=="failed")' .validation-audit/validation.jsonl | wc -l
```

**Recovery Path:**

Option A: **Fix and wait for retry** (< 1 hour next check)
```bash
# Fix the root cause
# Phase 4 automatically retries hourly
# Once fixed, validation will pass and continue

# Monitor progress
watch 'jq ".status" .validation-audit/validation.jsonl | tail -1'
```

Option B: **Skip Phase 4 validation** (risky)
```bash
# If absolutely critical to advance to Phase 5:
# (REQUIRES Security + Infrastructure approval)

# Create override flag
echo "{ \"override_phase_4\": true, \"timestamp\": \"$(date -Iseconds)\" }" > .override-phase-4

# Manually trigger Phase 5
gh workflow run phase-5-operations.yml
```

Option C: **Investigate transient vs permanent failure**
```bash
# Is the failure:
# - Transient (network hiccup, temp unavailability)? → Wait for retry
# - Permanent (deleted credentials, service down)? → Fix and retest
# - Permission issue (IAM)? → Update permissions and retest

# Run detailed diagnostics
bash scripts/validation/detailed_diagnostics.sh
```

---

### Phase 5 Failure: Operations & Ongoing Rotation

**Symptoms:**
- Daily rotation fails
- Hourly health checks fail
- Credentials not being rotated
- Services start using stale credentials
- Credential expiration imminent

**Immediate Actions (< 5 minutes):**

1. **Stop Phase 5 workflow:**
   ```bash
   gh run cancel --workflow phase-5-operations.yml
   ```

2. **Check when last rotation succeeded:**
   ```bash
   # Find last successful rotation
   jq 'select(.event=="rotation_complete" and .status=="successful")' \
      .operations-audit/operations.jsonl | jq '.timestamp' | tail -1
   ```

3. **Extend credential lifetime:**
   ```bash
   # Manually extend current credentials' lifetime
   # (Buy time while investigating)
   
   # For GSM:
   bash scripts/credentials/extend_gsm_credential_lifetime.sh
   
   # For Vault:
   bash scripts/credentials/extend_vault_lease.sh
   
   # For KMS:
   # (Keys don't expire if not set - no action needed)
   ```

4. **Check service health:**
   ```bash
   # Test all services with current credentials
   bash scripts/validation/full_health_check.sh
   ```

**Diagnosis (Next 30 minutes):**

```bash
# Review rotation failure logs
jq '.event == "rotation_failed"' .operations-audit/operations.jsonl | head -10

# Check which credentials are failing
jq '.credential_id, .error' .operations-audit/operations.jsonl | grep -A1 "rotation_failed"

# Count credential age
jq '.credential_age_days' .operations-audit/operations.jsonl | sort -n | tail -1
```

**Recovery Path:**

Option A: **Fix Phase 5 and resume rotation**
```bash
# Fix root cause:
# - Check credential backend availability (GSM/Vault/KMS)
# - Check network connectivity
# - Check service quotas/rate limits
# - Check IAM permissions

# Manually rotate once to verify fix works
bash scripts/credentials/perform_manual_rotation.sh

# Resume Phase 5
gh workflow run phase-5-operations.yml
```

Option B: **Manual rotation until Phase 5 fixed**
```bash
# Disable Phase 5 until fixed
gh workflow disable phase-5-operations.yml

# Manually rotate credentials daily (temporarily)
bash scripts/credentials/perform_manual_rotation.sh

# Rotate daily until Phase 5 is fixed and resumed
# Set in crontab:
# 0 2 * * * bash /path/to/perform_manual_rotation.sh >> /var/log/manual-rotation.log 2>&1
```

Option C: **Revert to static credentials** (emergency fallback)
```bash
# If rotation completely broken and credentials about to expire
# (REQUIRES all approvals + incident escalation)

# Disable Phase 5
gh workflow disable phase-5-operations.yml

# Revert to static credential mode
bash scripts/credentials/revert_to_static_mode.sh

# Set up manual credential management
# - Rotate manually weekly
# - Track rotation in manual spreadsheet
# - Plan proper fix for next maintenance window
```

---

## General Rollback Procedures

### Rollback Phase 2-3 (Revert OIDC Setup and Revocations)

```bash
#!/bin/bash
set -e

echo "🔄 Rolling back Phase 2-3..."

# 1. Stop workflows
gh run cancel --workflow "phase-[23]*.yml"

# 2. Restore GitHub Secrets from backup
# (Should have been backed up before Phase 2)
gh secret set GCP_WIF_PROVIDER_ID --body "$BACKUP_GCP_WIF_PROVIDER_ID"
gh secret set AWS_ROLE_ARN --body "$BACKUP_AWS_ROLE_ARN"
gh secret set VAULT_ADDR --body "$BACKUP_VAULT_ADDR"
gh secret set VAULT_JWT_ROLE --body "$BACKUP_VAULT_JWT_ROLE"

# 3. Restore revoked credentials in all backends
bash scripts/credentials/restore_revoked_credentials.sh

# 4. Verify services are operational
bash scripts/validation/full_health_check.sh all-services

# 5. Create rollback audit entry
jq -n "$(date -Iseconds) | .timestamp = . | .event = \"rollback_phase_2_3_complete\"" \
  >> .rollback-audit/rollback.jsonl

echo "✅ Phase 2-3 rolled back successfully"
```

### Rollback to Phase 1 Only (Complete Reset)

```bash
#!/bin/bash
set -e

echo "⚠️  COMPLETE ROLLBACK TO PHASE 1 - THIS IS DESTRUCTIVE"
read -p "Are you sure? Type 'YES' to confirm: " confirm
[[ "$confirm" == "YES" ]] || exit 1

# 1. Stop all workflows
gh run cancel --all --workflow "phase-*.yml"

# 2. Disable all workflows
gh workflow disable phase-2-oidc-wif-setup.yml
gh workflow disable phase-3-revoke-exposed-keys.yml
gh workflow disable phase-4-production-validation.yml
gh workflow disable phase-5-operations.yml

# 3. Delete all GitHub Secrets created by Phase 2
for secret in GCP_WIF_PROVIDER_ID AWS_ROLE_ARN VAULT_ADDR VAULT_JWT_ROLE; do
  gh secret delete "$secret" 2>/dev/null || true
done

# 4. Restore original credentials (from backup)
bash scripts/credentials/restore_original_credentials.sh

# 5. Clean up audit trails (optionally preserve in archive)
mkdir -p .audit-archive/$(date +%Y%m%d_%H%M%S)
mv .{oidc-setup,revocation,validation,operations}-audit \
   .audit-archive/$(date +%Y%m%d_%H%M%S)/

# 6. Verify services operational
bash scripts/validation/full_health_check.sh all-services

echo "✅ Rollback to Phase 1 complete"
echo "📦 Previous audit trails archived to: .audit-archive/"
```

---

## Communication During Rollback

### Incident Notification Template

```
🚨 INCIDENT: Multi-Phase Automation Failure

Phase: [2/3/4/5]
Time: [HH:MM UTC]
Duration: [TBD]
Impact: [No impact / Limited impact / Service impaired / Service down]

Root Cause: [Being investigated]
Action: [Rolled back to Phase X / Investigating / Fixed]
Status: [ONGOING / RESOLVED]

Updates every 15 minutes to: #incidents channel

Contact: [Primary On-Call Name]
```

### Escalation Notification

```
To: [All Stakeholders]
Cc: [CTO, Security Lead, Infrastructure Lead]

Subject: ROLLBACK INITIATED - Multi-Phase Automation Issue

The multi-phase credential automation has encountered a [Phase X] issue.
We have performed an emergency rollback to [Phase Y].

Timeline:
- [Time 1]: Failure detected
- [Time 2]: Emergency stop initiated
- [Time 3]: Rollback procedures started
- [Time 4]: Services restored to [previous state]
- [Time TBD]: Root cause analysis and fix
- [Time TBD]: Retry (pending approval)

Status: [INVESTIGATING / STABILIZED]
No customer impact expected.

Next update: [Time + 30 minutes]
```

---

## Post-Rollback Procedures

### 1. Incident Review

Schedule within 24 hours:

```
Participants: Engineering, Security, Operations, Management
Duration: 60-90 minutes

Agenda:
1. Timeline of events (0-10 min)
2. Root cause analysis (10-30 min)
3. Contributing factors (30-45 min)
4. Prevention for future (45-70 min)
5. Remediation plan (70-90 min)

Outputs:
- RCA document
- Action items with owners
- Lessons learned
- Updated runbooks
```

### 2. Fix and Retest

Before attempting Phase 2 again:

```bash
# 1. Fix the identified root cause
# (e.g., update GitHub Actions permissions, adjust cloud provider config)

# 2. Test Phase 2 in non-production environment (if possible)
# or with manual approvals between each phase

# 3. Post-incident review of rollback procedure
# (What worked well? What could be improved?)

# 4. Update EMERGENCY_ROLLBACK_PLAN.md with lessons learned

# 5. Brief full team on findings
```

### 3. Update Documentation

```bash
# Update based on incident:
- PRODUCTION_HARDENING_CHECKLIST.md (add new checks)
- GO_LIVE_CHECKLIST.md (add new gates)
- EMERGENCY_ROLLBACK_PLAN.md (add insights)
- All runbooks (refresh procedures)

# Commit changes
git add .
git commit -m "docs: update procedures based on incident [Issue #XXXX]"
git push origin main
```

---

## Rollback Testing Checklist

**Before Production Deployment, Test Rollback Procedures:**

- [ ] Simulate Phase 2 failure and test rollback
- [ ] Simulate Phase 3 partial failure (some creds revoked)
- [ ] Simulate Phase 4 validation failure
- [ ] Simulate Phase 5 rotation failure
- [ ] Test credential restoration from backup
- [ ] Verify service health after each rollback
- [ ] Verify audit trails preserved correctly
- [ ] Time each rollback procedure (document)
- [ ] Brief all on-call team on procedures
- [ ] Document any procedure issues found

---

## Key Contacts

```
┌─────────────────────────────────────────────┐
│ ROLL CALL - Print and Post in War Room      │
├─────────────────────────────────────────────┤
│ Primary On-Call:    _______________________  │
│ Secondary On-Call:  _______________________  │
│ Infrastructure:     _______________________  │
│ Security:          _______________________  │
│ Database:          _______________________  │
│ Cloud Ops (GCP):   _______________________  │
│ Cloud Ops (AWS):   _______________________  │
│ Vault Admin:       _______________________  │
│ CTO/Director:      _______________________  │
└─────────────────────────────────────────────┘
```

---

**Last Updated:** 2026-03-08  
**Next Review:** 2026-03-15  
**Current Approval:** _____________________ (Signature)
