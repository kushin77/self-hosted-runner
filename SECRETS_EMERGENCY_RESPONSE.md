# 🚨 SECRETS EMERGENCY RESPONSE PLAYBOOK

**Use this when something is BROKEN or EXPOSED in production.**

**Time Stamp Issue**: [Use ISO 8601: `date -u +%Y-%m-%dT%H:%M:%SZ`]

---

## PLAYBOOK #1: Secret Invalid/Truncated (GCP, Docker, etc.)

### Symptoms
```
❌ "failed to parse service account key JSON credentials: unexpected end of JSON input"
❌ "docker login: invalid credentials"
❌ Secret appears empty or corrupted in workflow logs
```

### Immediate Actions (< 5 minutes)

```bash
# Step 1: Acknowledge incident
# Post to #incidents Slack channel:
# "🚨 INCIDENT: GCP_SERVICE_ACCOUNT_KEY invalid. WIP on fix."

# Step 2: Identify scope
# Which workflows are affected?
gh run list --status failure | grep -E "docker-hub-dr|terraform|gcp|auth"

# Step 3: Disable affected workflows (temporary safety measure)
# Edit .github/workflows/docker-hub-weekly-dr-testing.yml
# Add to jobs: if: ${{ false }}  # DISABLED FOR INCIDENT

# Step 4: Create incident issue
gh issue create \
  --title "[INCIDENT] GCP_SERVICE_ACCOUNT_KEY invalid - Disabled workflows" \
  --label "incident,critical,secrets" \
  --body "GCP auth failed. Workflows disabled pending fix. Status: In Progress"

# Step 5: Notify team
# Ping @ops-team in #incidents Slack: "GCP secret invalid, investigating..."
```

### Fix (< 15 minutes)

```bash
# Step A: Validate what's wrong
echo "${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}" > /tmp/test.json
jq empty /tmp/test.json  # Will error if invalid JSON

# Step B: Get corrected secret
# Option 1: From backup (if available)
if [ -f ~/.backup/gcp-key-2026-02-01.json ]; then
  GCP_KEY=$(cat ~/.backup/gcp-key-2026-02-01.json)
fi

# Option 2: Generate new (if old is truly corrupted)
gcloud iam service-accounts keys create /tmp/new-key.json \
  --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com
GCP_KEY=$(cat /tmp/new-key.json)

# Step C: Validate new secret locally
jq empty <<< "$GCP_KEY"  # Must succeed

# Step D: Update GitHub secret atomically
gh secret set GCP_SERVICE_ACCOUNT_KEY --body "$GCP_KEY"

# Step E: Verify update
gh secret list | grep GCP_SERVICE_ACCOUNT_KEY

# Step F: Re-enable workflows
# Remove `if: ${{ false }}` from disabled workflows

# Step G: Test
gh workflow run verify-secrets-and-diagnose.yml --ref main
gh run list --workflow=verify-secrets-and-diagnose.yml --limit 1 | watch grep conclusion

# Step H: Re-enable dependent tests
gh workflow run docker-hub-weekly-dr-testing.yml --ref main
```

### Post-Recovery Documentation

```bash
# Update incident log
cat >> ROTATION_LOG.md << 'EOF'
## [2026-03-07T14:32:00Z] INCIDENT #1: GCP Secret Truncation

**Status**: 🟢 RESOLVED (fixed)

**Root Cause**: Previous rotation accidentally truncated secret value during copy-paste

**Timeline**:
- 14:15 UTC: Failed DR test detected via monitoring
- 14:20 UTC: Incident opened in GitHub
- 14:32 UTC: Secret re-generated and updated
- 14:45 UTC: All tests passing

**Fix**: 
- Regenerated GCP_SERVICE_ACCOUNT_KEY via `gcloud iam service-accounts keys create`
- Updated both GCP_SERVICE_ACCOUNT_KEY and TF_VAR_SERVICE_ACCOUNT_KEY
- Re-ran validation workflow successfully

**Prevention**: 
- Script rotation process to avoid manual copy-paste errors
- Add validation step to detect truncation before setting

**Post-Mortem**: Scheduled for 2026-03-08 @ 9 AM UTC

EOF

git add ROTATION_LOG.md
git commit -m "incident: log GCP secret truncation and fix [2026-03-07]"
git push origin main
```

---

## PLAYBOOK #2: Secret Exposed in Git/Logs

### Symptoms
```
❌ "Secret detected in commit history"
❌ Secret visible in GitHub Actions job logs
❌ Secret visible in public GitHub PR
```

### IMMEDIATE (DO THIS NOW - < 2 minutes)

```bash
# 1. Page on-call engineer NOW
# Slack: @on-call-security URGENT: Secret exposed in Git

# 2. Create emergency issue
gh issue create \
  --title "[SECURITY-EMERGENCY] Secret exposed: GCP_SERVICE_ACCOUNT_KEY" \
  --label "security,urgent" \
  --body "Secret exposed in commit 7f4e3a2. DO NOT MERGE. Rotating now."

# 3. If exposed in PR:
#    - Close PR immediately (don't merge!)
#    - Add comment "Exposed secret, closing"

# 4. Assume secret is compromised
#    → Proceed directly to rotation
```

### Rotation (< 15 minutes)

```bash
# This is same as Playbook #1 but FASTER
# Rotate IMMEDIATELY, don't wait for Monday

# 1. Generate new secret
gcloud iam service-accounts keys create /tmp/recovery-key.json \
  --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com

# 2. Verify format
jq empty /tmp/recovery-key.json

# 3. Update GitHub
gh secret set GCP_SERVICE_ACCOUNT_KEY < /tmp/recovery-key.json

# 4. Test immediately
gh workflow run verify-secrets-and-diagnose.yml

# 5. Delete old key from GCP (revoke immediately)
# Note old key ID:
OLD_KEY_ID=$(jq -r '.private_key_id' ~/.backup/gcp-key-before-exposure.json)
gcloud iam service-accounts keys delete "$OLD_KEY_ID" \
  --iam-account=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com \
  --quiet

# 6. Scan logs for what was exposed
# → Check if attacker used the key
gcloud logging read "resource.type=service_account AND protoPayload.authenticationInfo.principalEmail=self-hosted-runner@self-hosted-runner.iam.gserviceaccount.com" \
  --limit 1000 --format json > /tmp/gcp-audit-log.json

# 7. Analyze suspicious activity
cat /tmp/gcp-audit-log.json | jq '.[] | select(.protoPayload.request | . != null) | {time:.timestamp, operation:.protoPayload.methodName, user:.protoPayload.authenticationInfo.principalEmail}'
```

### Investigation & Remediation

```bash
# 8. Check what attacker could have accessed
# - If exposed for >30 minutes: Assume compromise
# - Rotate ALL GCP-related secrets (not just service account key)

# 9. Rewrite Git history to remove secret
# ⚠️ WARNING: This requires force-push and coordination

# Using BFG Repo-Cleaner (recommended):
bfg --delete-files /path/to/exposed-file.json
cd .bfg-report
# Review what got deleted
git push origin --force-with-lease

# OR using git filter-branch:
git filter-branch --force --tree-filter \
  'grep -r "AKIA\|ghp_\|-----BEGIN OPENSSH" . && echo "Found secret!" || true' \
  --prune-empty -- --all

git push --force-with-lease origin main  # ⚠️ Requires admin approval

# 10. Verify secret is gone
git log -p | grep -i "private_key\|password" | head -20
# Should be empty

# 11. Force all developers to re-clone
# Post in #dev channel: "Force-pushed main due to security incident. Please re-clone in ~/.tmp"
```

### Post-Incident (Same Day)

```bash
# 12. Document everything
cat >> ROTATION_LOG.md << 'EOF'
## [2026-03-07T16:45:00Z] SECURITY INCIDENT: Secret exposed in Git

**Severity**: 🔴 CRITICAL

**What Happened**: 
- GCP_SERVICE_ACCOUNT_KEY accidentally committed to Git
- Exposed for ~45 minutes before detection
- Visible in public GitHub history

**Immediate Actions**:
- Rotated GCP_SERVICE_ACCOUNT_KEY (new key generated)
- Old key revoked in GCP IAM
- Git history rewritten (BFG Repo-Cleaner)
- All developers notified to re-clone
- GCP audit logs reviewed

**Attacker Analysis**:
- GCP audit logs show no suspicious activity under old key
- Exposure was >30 minutes but likely didn't have time to exploit
- Status: Assume compromised (rotated as precaution)

**Root Cause**: Human error - copied-pasted secret into workflow file instead of GitHub Secret

**Prevention**: 
- Add pre-commit hook to detect secrets (using TruffleHog)
- Mandatory secrets training for all committers
- Require secrets review in all PRs

**Post-Mortem**: 2026-03-08 @ 10 AM UTC

EOF

git add ROTATION_LOG.md
git commit -m "security: document secret exposure incident [2026-03-07]"
git push origin main

# 13. Schedule post-mortem (same day if possible)
gh issue create \
  --title "Post-Mortem: Secret Exposure on 2026-03-07" \
  --label "post-mortem,security" \
  --body "Schedule post-mortem for exposed GCP_SERVICE_ACCOUNT_KEY. Topics: prevention, detection, response improvements."
```

---

## PLAYBOOK #3: Rotation Workflow Failing

### Symptoms
```
❌ credential-rotation-monthly.yml failed
❌ Workflow status: "Rotated secret" step failed
❌ Retry attempts exhausted (3/3)
```

### Diagnosis (< 10 minutes)

```bash
# 1. Check what specifically failed
gh run view <RUN_ID> --log-failed | head -100

# 2. Categorize failure:
#    a) Upstream service down (GCP, Docker Hub, Vault)?
#    b) Insufficient permissions (IAM scopes missing)?
#    c) Invalid old secret (using truncated value for rotation)?
#    d) GitHub API rate limit?

# 3. If upstream service is down:
#    → Wait 5 minutes and retry
#    → Manual rotation after 30 minutes if still down

# 4. If insufficient permissions:
#    → Check IAM scopes for service account
#    gcloud iam service-accounts get-iam-policy self-hosted-runner@...
#    → Add missing roles if needed

# 5. If invalid old secret:
#    → Use Playbook #1 to fix the invalid secret
#    → Then retry rotation

# 6. If rate limit:
#    → Wait 1 hour
#    → Retry rotation
```

### Recovery (< 30 minutes)

```bash
# Option A: Auto-retry (if transient failure)
gh run rerun <RUN_ID>

# Option B: Manual rotation (if systemic failure)
# Step 1: Generate new secret
gcloud iam service-accounts keys create /tmp/manual-rotate.json ...

# Step 2: Validate
jq empty /tmp/manual-rotate.json

# Step 3: Update GitHub
gh secret set GCP_SERVICE_ACCOUNT_KEY < /tmp/manual-rotate.json

# Step 4: Validate security
gh workflow run verify-secrets-and-diagnose.yml

# Step 5: Log as manual
cat >> ROTATION_LOG.md << 'EOF'
## [2026-03-XX] GCP_SERVICE_ACCOUNT_KEY - Manual Rotation

**Status**: 🟢 Manual rotation completed

**Reason**: Scheduled rotation workflow failed (GCP API timeout)  
**Performed By**: @your-username  
**Time**: ~30 minutes  

**Process**:
1. Generated new key via `gcloud iam service-accounts keys create`
2. Validated JSON locally
3. Updated GitHub secret manually
4. Enabled dependent workflows
5. Ran verification workflow

EOF
```

---

## PLAYBOOK #4: Cascade Failures After Rotation

### Symptoms
```
❌ 5+ workflows failing with permission/auth errors
❌ All failures occurred after scheduled rotation
❌ Pattern: "Invalid credentials for service X"
```

### Immediate Containment (< 5 minutes)

```bash
# 1. STOP all dependent workflows (add `if: false`)
#    This prevents cascade of failures
for WF in .github/workflows/{docker-hub,terraform,gcp}*.yml; do
  sed -i 's/jobs:/if: false\njobs:/' "$WF"
done
git add .github/workflows/*.yml
git commit -m "emergency: disable workflows [cascade failure]"
git push

# 2. Create emergency issue
gh issue create \
  --title "[EMERGENCY] Cascade failure after rotation - Workflows disabled" \
  --label "emergency,incident" \
  --body "5+ workflows failing after secret rotation. Disabled for safety."

# 3. Page on-call
# Slack: @on-call Urgent: cascade failure after secret rotation
```

### Investigation

```bash
# 1. Which rotation caused this?
tail -1 ROTATION_LOG.md

# 2. Was rotation successful at the time?
gh workflow run view <ROTATION_RUN_ID> --conclusion

# 3. What changed?
# Did GitHub cache old secret value? Did service not accept new key yet?
# → Wait 5-10 minutes (caches expire)

# 4. Test manually
gh workflow run verify-secrets-and-diagnose.yml

# 5. If manual test passes:
#    → Workflows likely just need to be re-run
gh run rerun <FAILING_RUN_ID>
```

### Recovery

```bash
# 1. If rotation is the culprit:
#    Rollback to previous secret (Playbook #1 + rollback section)

# 2. Or re-enable workflows and retry
for WF in .github/workflows/{docker-hub,terraform,gcp}*.yml; do
  sed -i 's/if: false\n//' "$WF"  # Remove if: false
done
git add .github/workflows/*.yml
git commit -m "emergency: re-enable workflows [cascade resolved]"
git push

# 3. Monitor for 30 minutes
# If failures continue → escalate to full incident

# 4. Document
cat >> ROTATION_LOG.md << 'EOF'
## Cascade failure post-mortem

- Workflows re-enabled at XXXXXX
- All tests passing as of XXXXXX
- Root cause: [GitHub cache / service delay]
- Prevention: Wait 5 minutes before re-running after rotation

EOF
```

---

## PLAYBOOK #5: Secret Expiration Alert (Proactive)

### Symptoms
```
⚠️ "Secret expires in 7 days"
⚠️ "RUNNER_MGMT_TOKEN expires 2026-06-03"
```

### Action (No Emergency, But Do Today)

```bash
# 1. Check which secret is expiring
grep "next_rotation_due:" SECRETS_CLASSIFICATION.yml | grep -E "202[6]-03-0[789]"

# 2. Start early rotation (don't wait until last day)
# Follow SECRETS_OPERATIONS_GUIDE.md → Rotation Procedures

# 3. Generate replacement
# (Use earliest convenient time, not midnight on due date)

# 4. Update secret
gh secret set SECRET_NAME --body "..."

# 5. Validate
gh workflow run verify-secrets-and-diagnose.yml

# 6. Log
cat >> ROTATION_LOG.md << 'EOF'
## [DATE] SECRET_NAME - Early rotation (proactive)

Rotated before expiration to ensure no downtime.
EOF
```

---

## Contact Tree (If All Else Fails)

```
┌─────────────────────────────┐
│  🚨 INCIDENT ESCALATION     │
└────────────┬────────────────┘
             │
             ▼
    Is it < 5 min to fix?
        YES / NO
        │     │
        ✓     ┌──────────────────────────────┐
        │     │ Slack: #incidents + @on-call │
        │     │ Email: OnCall@elevatediq.com │
        │     │ Page: PagerDuty (if severe)  │
        │     └──────────────────────────────┘
        │
        ▼
    On-call responds
        │
        ├─ If they can fix: Follow their guidance
        ├─ If escalation needed: Loop in @security-lead
        ├─ If multi-system: Loop in @platform-oncall
        └─ If financial impact: Loop in @cto

```

---

## Testing Playbooks (Do This Monthly)

```bash
# Test Playbook #1: Secret corruption simulation
# - Manually corrupt a NON-PROD secret
# - Follow Playbook #1 recovery steps
# - Time the fix (target < 15 minutes)

# Test Playbook #2: Secret exposure simulation
# - Commit a fake secret to a separate branch
# - Follow Playbook #2 remediation steps
# - Verify Git history rewrite works

# Test Playbook #3: Rotation failure simulation
# - Disable a rotation workflow temporarily
# - Trigger it manually and verify failure handling
# - Follow recovery steps

# Record times in spreadsheet: (Incident | Time to Fix | Owner | Date)
# Target: All playbooks < 30 minutes
```

---

**Last Updated**: 2026-03-07  
**Next Drill**: 2026-04-07  
**Owner**: @security-team  
**Questions**: #security-incidents on Slack
