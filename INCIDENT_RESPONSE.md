# INCIDENT RESPONSE & TROUBLESHOOTING GUIDE

**Last Updated**: 2026-03-09  
**System**: Enterprise Ephemeral Credential Infrastructure  
**Contact**: Operations Team

---

## QUICK START: INCIDENT RESPONSE MATRIX

| Issue | Symptoms | Quick Fix | Deep Dive |
|-------|----------|-----------|-----------|
| **No Credential** | "credential not found" | Check GSM/Vault/KMS status | See Section 2 |
| **Workflow Fails** | Red GitHub Actions run | Check health check logs | See Section 3 |
| **Audit Gap** | Missing audit entries | Query audit logs | See Section 4 |
| **Slow Retrieval** | >1 sec credential time | Check layer latency | See Section 5 |
| **Multi-Layer Down** | All layers failing | Execute recovery | See Section 6 |

---

## SECTION 1: CREDENTIAL RETRIEVAL DEBUGGING

### Symptom: `Error: Credential [SECRET_NAME] not found`

**Step 1: Verify Credential Action Output**
```bash
# Check GitHub Actions run logs for the step:
# "Get Credential [SECRET_NAME]"
# Look for: steps.cred_secret_name.outputs.credential

# If output is empty or error:
  → Credential action failed
  → Proceed to Step 2
```

**Step 2: Check OIDC Token Generation**
```bash
# In GitHub Actions, verify permissions are set:
permissions:
  id-token: write    # Must be present

# If missing:
  → Add id-token: write to permissions block
  → Re-run workflow
```

**Step 3: Verify Multi-Layer Endpoints**
```bash
# Check each layer is accessible:

# GSM (GCP):
gcloud secrets list --project=$GCP_PROJECT_ID

# Vault:
vault kv get secret/$SECRET_NAME

# KMS (AWS):
aws kms describe-key --key-id=$KMS_KEY_ID
```

**Step 4: Test Credential Action Manually**
```bash
# Simulate action execution:
docker run -e GITHUB_TOKEN=$TOKEN \
  -e GITHUB_WORKSPACE=/workspace \
  -e INPUT_CREDENTIAL-NAME=TEST_SECRET \
  -e INPUT_RETRIEVE-FROM=auto \
  -e INPUT_CACHE-TTL=600 \
  kushin77/get-ephemeral-credential:v1
```

### Recovery Actions

**If GSM Fails**:
```bash
# 1. Check GCP project access:
gcloud auth application-default print-access-token

# 2. Verify secret exists:
gcloud secrets versions list SECRET_NAME

# 3. Check service account permissions:
gcloud projects get-iam-policy $GCP_PROJECT_ID

# 4. If needed, re-sync from backup:
bash scripts/sync-gsm-from-backup.sh
```

**If Vault Fails**:
```bash
# 1. Check Vault connectivity:
vault status

# 2. Verify JWT auth method:
vault auth list | grep jwt

# 3. Check secret path:
vault kv get secret/$SECRET_NAME

# 4. If needed, restore from backup:
bash scripts/restore-vault-backup.sh
```

**If KMS Fails**:
```bash
# 1. Check AWS credentials:
aws sts get-caller-identity

# 2. Verify KMS key:
aws kms describe-key --key-id=$KMS_KEY_ID

# 3. Check permissions:
aws kms get-key-policy --key-id=$KMS_KEY_ID --policy-name default

# 4. If needed, use backup KMS key:
AWS_KMS_KEY_ID=$BACKUP_KMS_KEY_ID bash scripts/rotate-kms-key.sh
```

---

## SECTION 2: CREDENTIAL SYSTEM HEALTH CHECK

### Display Current System Status
```bash
# Run health check:
github-cli run workflow .github/workflows/credential-system-health-check-hourly.yml

# Or check last run:
gh run list -w credential-system-health-check-hourly.yml --limit 5

# View detailed output:
gh run view RUN_ID --log
```

### Parse Health Check Output
Health check workflow logs show:
```
✅ GSM Health: OK (response time: 150ms)
✅ Vault Health: OK (response time: 200ms)
✅ KMS Health: OK (response time: 180ms)
✅ Credential Retrieval: OK (count: 85 successful)
⚠️ Expiration Check: X credentials expiring in 24h
```

### What Each Status Means

**✅ OK**: Layer is operational and responding  
**⚠️ WARNING**: Layer responding but slow or expiring credentials  
**❌ FAILED**: Layer is down, proceeding with failover  

### Escalation Matrix

| Status | Action | Escalate If |
|--------|--------|------------|
| ✅ All OK | Monitor normally | N/A |
| ⚠️ 1 Warning | Investigate, monitor closely | >5 minutes |
| ⚠️ 2+ Warnings | Page on-call, investigate | Immediately |
| ❌ 1 Layer Failed | Layer should auto-failover | Failover not working |
| ❌ 2+ Layers Failed | INCIDENT: Page team lead | Immediately |
| ❌ 3 Layers Failed | CRITICAL: Page VP Eng | Immediately |

---

## SECTION 3: WORKFLOW EXECUTION DEBUGGING

### Symptom: GitHub Actions Workflow Fails

**Step 1: Identify Failure Point**
```bash
# Get workflow run:
gh run view RUN_ID

# Check which step failed:
gh run view RUN_ID --log | grep -A 5 "ERROR\|FAIL\|Error"

# Common failure steps:
# - "Get Credential [SECRET]" → Credential issue (see Section 1)
# - "Checkout" → Git access issue
# - "Login" → Authentication issue
# - "Deploy" → Permission issue
```

**Step 2: Check Workflow Permissions**
```bash
# View workflow file:
cat .github/workflows/WORKFLOW_NAME.yml

# Verify:
# 1. permissions.id-token: write (for OIDC)
# 2. credentials action exists before first run step
# 3. Environment variables use step outputs correctly
```

**Step 3: Manual Step Simulation**
```bash
# Run the failing step locally:
cd /home/akushnir/self-hosted-runner

# Set required env vars:
export GITHUB_ACTIONS=true
export GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}

# Run the command:
bash -c "STEP_COMMAND"

# If this succeeds, issue is GitHub Actions specific
```

### Recovery: Re-run Workflow
```bash
# Option 1: Re-run failed job:
gh run rerun RUN_ID --failed

# Option 2: Re-run entire workflow:
gh run rerun RUN_ID

# Option 3: Manually trigger workflow:
gh workflow run WORKFLOW_NAME.yml --ref main
```

---

## SECTION 4: AUDIT LOG VERIFICATION

### Symptom: Missing Audit Entries

**Step 1: Verify Audit Logging Enabled**
```bash
# Check workflow has audit enabled:
grep "audit-log: true" .github/workflows/WORKFLOW_NAME.yml

# If not found:
# - Add audit-log: true to credential step
# - Re-deploy workflow
# - Re-run to generate new audit entry
```

**Step 2: Query Audit Logs**
```bash
# Find audit logs:
find .audit_logs -name "*.log" -o -name "*.json" 2>/dev/null | head -20

# View recent entries:
tail -50 .audit_logs/credential-audit-*.log | grep WORKFLOW_NAME

# Search for specific credential:
grep "SECRET_NAME" .audit_logs/*.log | tail -10
```

**Step 3: Verify Audit Log Integrity**
```bash
# Check if logs are append-only (immutable):
stat .audit_logs/credentials-audit.log

# Verify log size increased (shouldn't decrease):
ls -lh .audit_logs/credentials-audit.log
# Size should increase over time, never decrease

# Check for tampering:
# Compare with git version:
git show HEAD:.audit_logs/credentials-audit.log | wc -l
# Should match current size or be smaller (appended only)
```

### Recover Missing Audit Entries

**If Recent Entries Missing**:
1. Check if audit-log is enabled in workflow
2. Re-run failed workflow to generate new audit entry
3. Verify new entry appears in audit logs

**If Gap Detected**:
1. Calculate missing time window
2. Review git history for that period
3. Manually reconstruct using git logs:
   ```bash
   git log --all --since="2026-03-08 10:00" --until="2026-03-08 12:00" --oneline
   ```

**If Suspected Tampering**:
1. STOP all credentialoperations immediately
2. Preserve current audit logs (git backup)
3. Contact security team
4. Review git history for unauthorized changes
5. Execute recovery procedure (see RECOVERY section)

---

## SECTION 5: PERFORMANCE DEBUGGING

### Symptom: Credential Retrieval Taking >1 Second

**Step 1: Identify Slow Layer**
```bash
# Check credential action output:
# Look for: "source-layer: GSM" or "Vault" or "KMS"
# This indicates which layer responded

# In action output:
# "cached: true" → retrieval from cache (should be <100ms)
# "cached: false" → retrieval from storage (1-2 seconds normal)
```

**Step 2: Benchmark Each Layer**
```bash
# GSM benchmark:
time gcloud secrets versions access latest --secret=TEST_SECRET --project=$GCP_PROJECT_ID

# Vault benchmark:
time vault kv get secret/TEST_SECRET

# KMS benchmark:
time aws kms describe-key --key-id=$KMS_KEY_ID --region us-east-1
```

**Step 3: Check Network Latency**
```bash
# To GCP:
ping -c 5 www.googleapis.com

# To Vault:
ping -c 5 $VAULT_ADDR

# To AWS:
ping -c 5 sts.amazonaws.com
```

### Optimization: Enable Credential Caching
```bash
# Credential action already caches 15 minutes
# Verify cache is working:

# Look for "cached: true" in action output
# If "cached: false" every time:
# 1. Check cache-ttl setting (default 600s = 10 min)
# 2. Increase cache-ttl in workflow if desired:
#    cache-ttl: 1800  # 30 minutes

# WARNING: Longer cache = longer credential lifetime
# Keep <1 hour for security
```

---

## SECTION 6: MULTI-LAYER FAILURE RECOVERY

### Critical Scenario: All Credential Layers Down

**EMERGENCY PROCEDURES**:

**Step 1: Immediate Triage**
```bash
# Check all layers:
echo "GSM Status:" && gcloud secrets list 2>/dev/null | head -1 || echo "  FAILED"
echo "Vault Status:" && vault status 2>/dev/null | head -1 || echo "  FAILED"  
echo "KMS Status:" && aws kms list-keys 2>/dev/null | head -1 || echo "  FAILED"
```

**Step 2: Enable Fallback Mode** (if implemented)
```bash
# Switch to GitHub secrets fallback (temporary):
export USE_GITHUB_SECRETS_FALLBACK=true

# Re-run workflows:
gh workflow run ci-images.yml

# This allows 24-hour blind operation while investigating
```

**Step 3: Parallel Recovery Efforts**

**GSM Recovery**:
```bash
# Check GCP project status:
gcloud projects describe $GCP_PROJECT_ID --no-user-output

# Try alternative GSM instance:
export GCP_PROJECT_ID=$BACKUP_GCP_PROJECT_ID
bash scripts/rotate-gsm-primary.sh

# If successful, mark as primary again
```

**Vault Recovery**:
```bash
# Check Vault cluster:
vault status

# If sealed, unseal:
vault operator unseal

# Restore from backup:
bash scripts/restore-vault-backup.sh

# If primary down, promote secondary:
bash scripts/promote-vault-secondary.sh
```

**KMS Recovery**:
```bash
# Check AWS account access:
aws sts get-caller-identity

# Switch to backup KMS key:
export AWS_KMS_KEY_ID=$BACKUP_KMS_KEY_ID

# If key access revoked, enable in KMS:
aws kms enable-key --key-id $AWS_KMS_KEY_ID

# Verify new key works:
bash scripts/test-kms-encryption.sh
```

**Step 4: Validation**
```bash
# Run full health check:
bash scripts/phase6-production-validation.sh

# If all layers restored:
# 1. Exit fallback mode: unset USE_GITHUB_SECRETS_FALLBACK
# 2. Resume normal operations
# 3. Audit: Documented incident in audit logs
# 4. Post-incident: Schedule RCA with team
```

---

## SECTION 7: EMERGENCY ESCALATION

### On-Call Contact Tree
```
Level 1: GitHub Actions Workflow Issues
  → Check health check logs
  → Contact: Operations team
  → Response SLA: 15 minutes

Level 2: Credential Layer Failures
  → Check multi-layer fallover
  → Contact: Platform team  
  → Response SLA: 5 minutes

Level 3: Multi-Layer Failure
  → Activate emergency procedures
  → Contact: VP Engineering  
  → Response SLA: IMMEDIATE
  
Level 4: Suspected Security Breach
  → STOP all operations
  → Contact: Security team
  → Response SLA: IMMEDIATE
```

### After-Hours Support
```
See CODEOWNERS file for on-call rotation
Emergency: Page via PagerDuty (see setup)
Escalation: VP Engineering direct line
```

---

## QUICK REFERENCE: TOP 5 FIXES

1. **"Credential not found"**: Check GSM/Vault/KMS endpoints
2. **Workflow fails**: Verify permissions.id-token: write
3. **Slow retrieval**: Check layer latency with ping
4. **Missing audits**: Verify audit-log: true in workflow
5. **All systems down**: Enable GitHub secrets fallback

---

**REMEMBER**: When in doubt, check the health check workflow logs first!  
**Always log incidents**: Document in incident tracking system

**Questions?** See SUPPORT_CONTACTS.md
