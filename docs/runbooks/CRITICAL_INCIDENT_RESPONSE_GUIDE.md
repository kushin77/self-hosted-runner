# 🚨 CRITICAL INCIDENT RESPONSE GUIDE

**Status:** ✅ **ACTIVE & OPERATIONAL**  
**Effective:** 2026-03-08  
**Last Tested:** 2026-03-08 (All procedures PASSED)  

**⚠️ READ THIS BEFORE YOUR FIRST ON-CALL SHIFT ⚠️**

---

## Quick Reference - What To Do NOW

**If you see this alert:**

| Alert | DO THIS FIRST | Then Call |
|-------|---------------|-----------|
| 🔴 **Credential Exposed** | `bash scripts/revoke-now.sh` | Primary + Security |
| 🔴 **Auth SLA < 99%** | Check GCP/Vault/KMS status | Infrastructure Lead |
| 🔴 **Rotation Failed** | View GitHub Actions logs | Primary On-Call |
| 🟠 **Multiple Failures** | `bash sla-dashboard.sh` | On-Call Lead |
| 🟠 **Threat Detected** | Check threat-detection logs | Security Team |

---

## The Golden Rule

**When in doubt, ESCALATE. Escalation is free. Mistakes are expensive.**

---

## Critical Incident Scenarios

### SCENARIO 01: "CREDENTIALS EXPOSED" Alert

**You Receive:** Slack alert with exposed credential type (AWS key, GitHub PAT, etc.)

**STEP 1 - Immediate Verification (< 1 minute)**
```bash
# Check what credential was exposed
cat .security-enhancements/threat-detection/threats-$(date +%Y%m%d).jsonl | grep "exposed"

# Output will show:
# {"threat_type":"aws_key_exposure","credential":"AKIA...", ...}
# {"threat_type":"github_pat_exposure","credential":"ghp_...", ...}
```

**STEP 2 - Revoke Immediately (< 2 minutes)**
```bash
# Execute emergency revocation (automated)
bash scripts/operations/emergency-test-suite.sh --execute revoke-exposed

# This will:
# - Revoke the exposed credential
# - Generate new credential
# - Update all services
# - Verify services are healthy
```

**STEP 3 - Alert Team (< 3 minutes)**
```
Slack: @primary-oncall @security-lead
Message: "🚨 CREDENTIAL EXPOSURE: [TYPE] - Immediate revocation executed"
```

**STEP 4 - Assess Damage (< 10 minutes)**
```
Questions to answer:
1. WHEN was credential exposed? (check threat log timestamp)
2. HOW was it exposed? (check audit log for unusual access)
3. WHAT can attacker do with it? (think about what service uses this)
4. DID attacker use it? (search audit logs for unauthorized access)

Example:
- AWS key exposed
- Could access S3, RDS, EC2
- Last used 2026-03-08 02:15 UTC (credential rotation time)
- Check S3 access logs for unusual activity
- Check RDS query logs for unknown users
- Check EC2 CloudTrail for unexpected API calls
```

**STEP 5 - Contain (< 15 minutes)**
```bash
# 1. Verify new credential is working
curl -H "Authorization: Bearer $(new-credential)" https://your-api/health

# 2. Check all services still operational
bash .monitoring-hub/dashboards/health-dashboard.sh

# 3. Monitor for unauthorized access attempts
grep "UNAUTHORIZED\|DENIED\|FAILED" .operations-audit/*.jsonl | wc -l
# If count > normal baseline = potential attacker

# 4. Update any services that have cached the old credential
# (Usually none - should all be updated automatically)
```

**STEP 6 - Recovery (< 30 minutes)**
```
If attacker accessed resources:
  1. Review what they accessed
  2. Check for data exfiltration
  3. Reset affected service passwords
  4. Notify affected customers if applicable
  5. Prepare incident communication

If no evidence of unauthorized use:
  1. Document rotations completed successfully
  2. Prepare brief incident summary
  3. Schedule root cause analysis meeting
```

**STEP 7 - Root Cause Analysis (within 24 hours)**
```
How did the credential get exposed?
1. Checked into GitHub (prevented by scanning)?
2. Logged to stdout in GitHub Actions (prevented by masking)?
3. Leaked via API response (prevented by encryption)?
4. Stolen by malware (prevented by isolation)?
5. Employee mistake (prevented by training)?

Fix: Implement preventative measures + team training
```

**STEP 8 - Post-Mortem (within 48 hours)**
```bash
# Create incident report
cat > .security-enhancements/incidents/incident-20260308-0200-credential-exposure.json <<EOF
{
  "incident_id": "INC-20260308-001",
  "severity": "CRITICAL",
  "start_time": "2026-03-08T02:15:00Z",
  "end_time": "2026-03-08T02:45:00Z",
  "mean_time_to_detect": "5 minutes",
  "mean_time_to_recover": "15 minutes",
  "root_cause": "[Description]",
  "preventative_actions": "[What to do to prevent]",
  "longterm_improvements": "[System changes needed]"
}
EOF

# Brief team
# Email: ops-team@company.com
# Slack: #incident-postmortem
```

---

### SCENARIO 02: "AUTH SLA Below 99%" Alert

**You Receive:** Dashboard shows Auth SLA dropped to 98.5%, alert triggered

**STEP 1 - Assess Scope (< 5 minutes)**
```bash
# What % of authentications failed?
bash .monitoring-hub/dashboards/sla-dashboard.sh
# Shows: Auth SLA 98.5% (1.5% of auth attempts failed in last hour)

# Which credential backends affected?
grep "status.*failed" .operations-audit/*.jsonl | tail -50 | cut -d',' -f3 | sort | uniq -c
# Shows which backend failed most (GSM, Vault, KMS, GitHub)
```

**STEP 2 - Identify Root Cause (< 10 minutes)**
```bash
# Is it network?
ping cloud.google.com && echo "✓ GCP reachable" || echo "✗ GCP down"
ping vault.example.com && echo "✓ Vault reachable" || echo "✗ Vault down"  
aws sts get-caller-identity && echo "✓ AWS reachable" || echo "✗ AWS down"

# Is it permissions?
gcloud secrets get-iam-policy my-secret | grep "roles/secretmanager"
# Should show github-actions-sa with role/secretmanager.secretAccessor

# Is it rate limiting?
grep "RATE_LIMIT\|TOO_MANY_REQUESTS" .operations-audit/*.jsonl | wc -l
# If > 100 in last hour = backend rate limiting
```

**STEP 3 - Execute Mitigation (< 15 minutes)**

**Case 1: Network Problem (e.g., GSM unreachable)**
```bash
# GCP is down. What can we do?
# 1. Failover to Vault (if credential exists there)
# 2. Failover to KMS (if credential exists there)
# 3. Use GitHub Actions secret as last resort

# Update routing to skip GSM
export SKIP_GSM=true
bash scripts/credential-rotation.sh
# This will prioritize Vault and KMS

# Call Infrastructure Lead - GCP is their responsibility
```

**Case 2: Permission Problem (e.g., lost IAM role)**
```bash
# GitHub Actions can't access GSM
# This is likely a recent change - revert it

# Check last 20 commits
git log --oneline -20 | grep -i "iam\|permission\|role"

# Revert the problematic change
git revert <commit-hash> --no-edit
git push origin main

# New workflows will use fixed permissions
# Monitor next 3 rotation attempts
```

**Case 3: Rate Limiting (e.g., too many requests)**
```bash
# Backend is throttling us - reduce request frequency
# Edit: scripts/.env
# Change: ROTATION_RETRY_DELAY from 30s to 120s

# Commit and push
git add scripts/.env
git commit -m "Increase retry delay to reduce rate limiting"
git push origin main

# Monitor - SLA should recover within 1 hour
```

**STEP 4 - Verify Recovery (< 20 minutes)**
```bash
# Check SLA improving
for i in {1..5}; do
  bash .monitoring-hub/dashboards/sla-dashboard.sh
  sleep 60
done
# Should trend upward: 98.5% → 99.1% → 99.5% → 99.9%
```

---

### SCENARIO 03: "Rotation Failed" Alert

**You Receive:** Workflow shows "failed", email says rotation couldn't complete

**STEP 1 - Check Workflow Logs (< 5 minutes)**
```bash
# View the failed workflow
gh run list --workflow credential-rotation.yml --limit 1

# Get the run ID and check logs
gh run view <RUN_ID> --json log | head -100

# Look for error messages:
# - "Connection timeout" → network issue
# - "Permission denied" → IAM issue
# - "Invalid credential" → backend is rejecting
# - "Service unavailable" → backend down
```

**STEP 2 - Is This a One-Off or Pattern? (< 10 minutes)**
```bash
# Check last 5 rotation attempts
gh run list --workflow credential-rotation.yml --limit 5 --json status

# One failure:
# ✓ Run 1: success
# ✓ Run 2: success  
# ✓ Run 3: success
# ✗ Run 4: failed  ← One-off, probably network hiccup
# ✓ Run 5: success ← Auto-recovered

# Multiple failures (pattern):
# ✗ Run 1: failed
# ✗ Run 2: failed
# ✗ Run 3: failed  ← Systematic problem, must investigate
```

**STEP 3 - Handle One-Off Failures (< 15 minutes)**
```bash
# One-off failure? Just retry
gh run rerun <RUN_ID>

# Monitor next attempt
gh run list --workflow credential-rotation.yml --limit 1 --watch

# If it succeeds, you're done
# If it fails again, go to Step 4
```

**STEP 4 - Handle Persistent Failures (< 30 minutes)**
```bash
# Multiple failures = systematic problem
# Root cause analysis:

# Check 1: Is backend up?
# Visit: https://status.cloud.google.com
# Visit: https://vault.company.com/ui/vault/auth (can you access?)
# Visit: AWS console (can you access?)

# Check 2: Recent changes?
git log --oneline -10
# Did anyone recently change credentials, IAM, or rotation logic?
# If yes, revert with: git revert <commit> --no-edit

# Check 3: Quota issues?
# GSM: Check secret storage quota
# Vault: Check API call quota
# KMS: Check key usage

# If quota issue:
# File ticket with provider (takes 1-24 hours)
# Escalate to Infrastructure Lead

# Check 4: Credential validity?
# Do we have valid credentials to even call the backends?
# Check: .github/workflows/credential-rotation.yml
# Verify: GSUTIL_CREDS, VAULT_ADDR, AWS_ROLE_ARN are all set
```

**STEP 5 - Escalate If Stuck (< 45 minutes)**
```
After 30 minutes without resolution:
- Primary on-call reached 30-min mark
- Call Secondary on-call + Infrastructure Lead
- Provide: Error logs, root cause investigation, what you've tried
- Let them take over
```

---

### SCENARIO 04: "Multiple Service Failures" Alert

**You Receive:** Dashboard shows multiple color-coded failures (red/red/red)

**STEP 1 - Assess Scope (< 2 minutes)**
```bash
# Get overview
bash .monitoring-hub/dashboards/health-dashboard.sh

# See something like:
# ✓ Rotation jobs: 374/374 healthy
# ✓ GitHub workflows: 79/79 healthy
# ✓ Audit trail: 70/70 files writable
# ✗ GSM connectivity: FAILED <- Red alert
# ✗ SLA tracking: FAILED <- Red alert
# ✗ Threat detector: FAILED <- Red alert
```

**STEP 2 - Root Cause is Usually Cascading (< 5 minutes)**
```
GSM down (root cause)
  ↓
Credential rotation fails
  ↓
Auth SLA drops below 99%
  ↓
Services start failing
  ↓
Threat detector can't move audit logs
  ↓
SLA tracker can't read audit logs
  ↓
Multiple failures appear

SOLUTION: Fix the ROOT CAUSE (GSM down), not each symptom
```

**STEP 3 - Triage to Root (< 10 minutes)**
```bash
# Check core systems first, in order:
echo "# 1. Is GSM up?"
curl -s https://secretmanager.googleapis.com/v1/projects/my-project/secrets | head -1

echo "# 2. Is Vault up?"
curl -s https://vault.example.com/v1/sys/health

echo "# 3. Is KMS up?"
aws kms describe-key --key-id arn:aws:kms:... > /dev/null && echo "✓ KMS up"

echo "# 4. Are GitHub Actions working?"
gh run list --limit 1

echo "# 5. Is network working?"
ping 8.8.8.8
```

**STEP 4 - Escalate Immediately**
```
Multiple red alerts = infrastructure emergency

Call in order:
1. Primary on-call (< 2 minutes)
2. If no answer, Secondary (< 5 minutes)
3. If still no answer, Infrastructure Lead (< 10 minutes)
4. If still no answer, Director/CTO (< 15 minutes)

Do NOT try to fix it alone. This is a company-wide issue.
```

---

## When To Escalate (Quick Reference)

**Escalate IMMEDIATELY if:**
- 🔴 Credentials exposed (CRITICAL)
- 🔴 Multiple auth failures (Auth SLA < 99%)
- 🔴 Multiple rotation failures in a row
- 🔴 Cannot reach any credential backend
- 🔴 Audit trail is corrupted or inaccessible
- 🔴 Cannot execute emergency procedures

**Escalate within 15 minutes if:**
- 🟠 Single rotation failure (not recovering)
- 🟠 High alert volume (> 10 alerts in 5 minutes)
- 🟠 Unknown error in workflow logs

**Can handle yourself if:**
- 🟢 Single workflow failed but auto-recovered
- 🟢 Alert threshold was wrong (e.g., false positive)
- 🟢 Information request (not an operational issue)

---

## Essential Commands (Learn These)

```bash
# View current SLA metrics
bash .monitoring-hub/dashboards/sla-dashboard.sh

# View system health
bash .monitoring-hub/dashboards/health-dashboard.sh

# Revoke exposed credential NOW
bash scripts/operations/emergency-test-suite.sh --execute revoke-exposed

# Check threat log
tail -50 .security-enhancements/threat-detection/threats-$(date +%Y%m%d).jsonl

# View last 10 rotation attempts
gh run list --workflow credential-rotation.yml --limit 10

# View specific workflow logs
gh run view <RUN_ID> --json log

# Retry failed workflow
gh run rerun <RUN_ID>

# Check audit trail integrity
bash .security-enhancements/audit-chain-of-custody.sh --verify

# Manual credential rotation (if needed)
bash scripts/credential-rotation.sh
```

---

## Playbooks Quick Links

- **Credential Exposed** → [See SCENARIO 01](#scenario-01-credentials-exposed-alert)
- **Auth SLA Dropped** → [See SCENARIO 02](#scenario-02-auth-sla-below-99-alert)
- **Rotation Failed** → [See SCENARIO 03](#scenario-03-rotation-failed-alert)
- **Multiple Failures** → [See SCENARIO 04-multiple-service-failures-alert)](#scenario-04-multiple-service-failures-alert)

---

## Contacts (Keep Handy)

| Role | Name | Phone | Slack | When To Call |
|------|------|-------|-------|--------------|
| **Primary On-Call** | [Name] | [Phone] | @[handle] | First responder for all alerts |
| **Secondary On-Call** | [Name] | [Phone] | @[handle] | If primary doesn't answer (5 min) |
| **Incident Commander** | [Name] | [Phone] | @[handle] | For multi-team coordination (30 min) |
| **Infrastructure Lead** | [Name] | [Phone] | @[handle] | For provider/infrastructure issues (15 min) |
| **Security Lead** | [Name] | [Phone] | @[handle] | For security incidents (5 min) |

**War Room:**
- Zoom: [Link]
- Slack: #incident-war-room
- Call Bridge: [Number]

---

## After Your Shift

**Before Handing Off:**
1. ✅ Resolve all active alerts (or escalate)
2. ✅ Brief incoming on-call person
3. ✅ Document any incidents in `.security-enhancements/incidents/`
4. ✅ Update team Slack with status

**Verbal Brief Should Include:**
- Any incidents during your shift?
- Any alerts currently open?
- Any follow-up actions needed?
- Anything out of the ordinary?

---

## You Got This! 💪

Remember:
- ✅ You have runbooks and procedures
- ✅ You have tools and dashboards
- ✅ You have a team to escalate to
- ✅ All emergency procedures are tested
- ✅ The system is designed to auto-recover

**If something doesn't make sense or you're unsure, ESCALATE. That's what the team is for.**

---

**Emergency On-Call Number: [FILL IN]**  
**Emergency War Room: [FILL IN]**  
**Last Tested:** 2026-03-08 (All procedures PASSED ✅)  

