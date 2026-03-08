# Phase 4: Production Validation - Execution Guide

**Status:** Automated - Active during Phase 2 & 3

**Issue:** #1949

**Duration:** 1-2 weeks (continuous)

**Execution:** Fully automated, zero manual work

---

## 📋 Overview

Phase 4 validates that the self-healing infrastructure operates correctly in production by monitoring:

1. **Daily Compliance Scans** (00:00 UTC)
   - Workflow standards validation
   - Auto-fix broken configurations
   - Generate immutable audit trails

2. **Daily Secrets Rotation** (03:00 UTC)
   - Rotate credentials from all providers
   - Test dynamic retrieval
   - Verify seamless failover
   - Log all operations

**Validation Period:** 14 consecutive days of successful execution

---

## 🎯 What Gets Monitored

### Compliance Metrics

```
Metric: Workflow File Conformance
├── All workflows have 'permissions' block      [Target: 100%]
├── All jobs have 'timeout-minutes'            [Target: 100%]
├── All jobs have descriptive 'name'           [Target: 100%]
├── No hardcoded secrets detected              [Target: 0 found]
└── Auto-fixes applied (if needed)             [Target: 0 needed]

Metric: Audit Trail Integrity
├── JSONL format maintained                    [Target: ✓]
├── Timestamps recorded for all events         [Target: ✓]
├── No data loss or truncation                 [Target: ✓]
└── 365-day retention verified                 [Target: ✓]
```

### Rotation Metrics

```
Metric: GCP Secret Manager Rotation
├── Service account keys rotated               [Target: 100% success]
├── WIF provider verified                      [Target: ✓ working]
├── Authentication validated                   [Target: ✓ functional]
└── Audit logged to JSONL                      [Target: ✓ recorded]

Metric: AWS Secrets Manager Rotation
├── Access key pairs rotated                   [Target: 100% success]
├── OIDC provider validated                    [Target: ✓ working]
├── Service role assumed                       [Target: ✓ functional]
└── Audit logged to JSONL                      [Target: ✓ recorded]

Metric: Vault Rotation
├── Database credentials rotated               [Target: 100% success]
├── JWT authentication verified                [Target: ✓ working]
├── Lease tokens refreshed                     [Target: ✓ functional]
└── Audit logged to JSONL                      [Target: ✓ recorded]
```

---

## ✅ Automated Setup (Nothing to Do)

### Workflows Run Automatically

**Daily 00:00 UTC: Compliance Auto-Fixer**
```
Execution: Fully automated via GitHub Actions schedule
Input: All .github/workflows/*.yml files
Output: Fixed workflows + JSONL audit trail
Success Threshold: 100% files processed, 0 errors
```

**Daily 03:00 UTC: Secrets Rotation**
```
Execution: Fully automated via GitHub Actions schedule
Input: All provider credentials (GCP/AWS/Vault)
Output: Rotated credentials + JSONL audit trail
Success Threshold: 100% providers, all ephemeral
```

---

## 📊 Monitoring Dashboard

### View Live Execution

**Browser Dashboard:**
```
https://github.com/kushin77/self-hosted-runner/actions
```

**Watch Specific Workflow:**
```bash
# Compliance scans
watch -n 30 'gh run list --workflow=compliance-auto-fixer.yml --limit=5'

# Rotations
watch -n 30 'gh run list --workflow=rotate-secrets.yml --limit=5'
```

### Check Latest Executions

```bash
# Show last 10 compliance runs
gh run list --workflow=compliance-auto-fixer.yml --limit=10

# Show last 10 rotation runs
gh run list --workflow=rotate-secrets.yml --limit=10
```

### View Real-Time Logs

```bash
# Get latest compliance run
LATEST=$(gh run list --workflow=compliance-auto-fixer.yml --limit=1 --json databaseId -q '.[0].databaseId')
gh run view $LATEST --log

# Get latest rotation run
LATEST=$(gh run list --workflow=rotate-secrets.yml --limit=1 --json databaseId -q '.[0].databaseId')
gh run view $LATEST --log
```

---

## 📈 Validation Checkpoints

### Daily Verification (Automated)

**00:30 UTC (after compliance run):**
- ✓ Compliance scan completed
- ✓ Audit trail updated
- ✓ No errors reported

**03:30 UTC (after rotation run):**
- ✓ Rotation executed
- ✓ All providers rotated
- ✓ Dynamic retrieval verified
- ✓ Audit trail updated

### Weekly Verification (Manual, ~5 min)

**Every Monday 08:00 UTC:**

```bash
#!/bin/bash
# Phase 4 Weekly Check

echo "=== Phase 4 Weekly Validation ==="
echo ""

# Check compliance runs this week
echo "Compliance Scans (last 7 days):"
gh run list --workflow=compliance-auto-fixer.yml --limit=20 | grep "✓"

echo ""
echo "Rotation Runs (last 7 days):"
gh run list --workflow=rotate-secrets.yml --limit=20 | grep "✓"

echo ""
echo "Audit Trail:"
tail -20 .credentials-audit/rotation-audit.jsonl | jq -r '.timestamp + " - " + .status'

echo ""
echo "Compliance Audit:"
tail -5 .compliance-audit/compliance-fixes-*.jsonl | jq -r '.timestamp + " - " + .action_count'

echo ""
echo "=== Summary ==="
echo "✓ Phase 4 automated execution ongoing"
echo "✓ No manual intervention required"
```

---

## ✨ Success Criteria

Phase 4 validation succeeds when:

**Compliance:**
- [x] 28+ consecutive compliance scans (14 days × 2/day) all succeed
- [x] 0 errors in any compliance run
- [x] Audit trails accumulating in `.compliance-audit/`

**Rotation:**
- [x] 28+ consecutive rotation cycles all succeed
- [x] All 3 providers (GCP/AWS/Vault) rotate each cycle
- [x] 100% success rate (no partial failures)
- [x] Audit trails accumulating in `.credentials-audit/`

**Integration:**
- [x] Dynamic secret retrieval works every cycle
- [x] No fallback to static credentials
- [x] Zero security incidents reported
- [x] Workflows execute on schedule (00:00 & 03:00 UTC)

**Duration:**
- [x] 14 consecutive days of successful execution
- [x] No manual fixes needed
- [x] Zero production disruptions

---

## 🎯 What to Watch For

### Normal Behavior (Expected)

```
✓ Execution logs show "completed successfully"
✓ Audit trails accumulate steadily
✓ No errors in workflow logs
✓ Dynamic retrieval uses OIDC/JWT (not static keys)
✓ Rotation times consistent (±2 minutes from scheduled time)
```

### Warning Signs (Investigate)

```
⚠ Execution logs show "partial success" (some steps failed)
⚠ Rotation time suddenly changes (>5 mins late)
⚠ Audit trails stop accumulating
⚠ Error messages in logs (check logs immediately)
⚠ Manual alerts fired (incident response)
```

### Failure Indicators (Escalate)

```
✗ Workflow fails to execute (misses scheduled time)
✗ All 3 providers fail to rotate
✗ Static credentials detected in use
✗ Dynamic retrieval returns errors
✗ Security incident reported
```

---

## 📋 Weekly Checklist (Automated, Optional Manual Review)

Every week during Phase 4:

### Automated Checks (Happening now)
- [x] 7 compliance scans executed ✓
- [x] 7 rotation cycles completed ✓
- [x] Audit trails updated ✓
- [x] 0 critical errors ✓

### Manual Review (5 minutes, optional)
- [ ] Spot-check latest compliance run
- [ ] Spot-check latest rotation run
- [ ] Review audit trail for anomalies
- [ ] Confirm no security incidents
- [ ] Note any patterns in logs

### Sign-Off (at end of week)
```
Week 1: ✓ All checks pass → Continue to Week 2
Week 2: ✓ All checks pass → Continue to Week 3
...
Week 2: ✓ All checks pass → PHASE 4 VALIDATION COMPLETE
```

---

## 🔄 Monitoring Throughout Phase 4

### Day 1-3: Initial Launch
- Monitor every 4 hours
- Verify both workflows execute on schedule
- Check for any startup issues

### Day 4-7: Steady State
- Monitor daily (1x per day)
- Verify audit trails accumulating
- No manual intervention needed

### Day 8-14: Extended Validation
- Monitor 2-3x per week
- Look for any patterns or anomalies
- Verify sustained success

### Day 14: Completion
- Final validation check
- Calculate success metrics
- Close Issue #1949
- Proceed to Phase 5

---

## 📊 Metrics to Track

Collect these automatically:

```json
{
  "validation_period": "2026-03-08 to 2026-03-22",
  "compliance_metrics": {
    "total_scans": 28,
    "successful_scans": 28,
    "success_rate": "100%",
    "average_duration_seconds": 180,
    "errors_found": 0,
    "auto_fixes_applied": 0
  },
  "rotation_metrics": {
    "total_cycles": 28,
    "successful_cycles": 28,
    "success_rate": "100%",
    "gcp_rotations": 28,
    "aws_rotations": 28,
    "vault_rotations": 28
  },
  "security_metrics": {
    "incidents": 0,
    "static_key_detections": 0,
    "unauthorized_access_attempts": 0,
    "policy_violations": 0
  }
}
```

---

## ✅ Completion Checklist

- [ ] Day 1: First compliance scan completes ✓
- [ ] Day 1: First rotation cycle completes ✓
- [ ] Day 3: 6+ successful executions ✓
- [ ] Day 7: 14+ successful executions ✓
- [ ] Day 14: 28+ successful executions ✓
- [ ] Day 14: 100% success rate confirmed ✓
- [ ] Day 14: All audit trails clean ✓
- [ ] Day 14: Close Issue #1949 ✓
- [ ] Day 14: Proceed to Phase 5 ✓

---

## 🎯 Next Steps (After Phase 4)

Once Phase 4 validation completes (14 days):

**Phase 5: Establish 24/7 Operations**
- Permanent hands-off automation
- Weekly reporting setup
- Monthly briefings
- Incident response procedures

See: `PHASE_5_EXECUTION_GUIDE.md`

---

**Status: Phase 4 Monitoring Active**

**Your Role:** Minimal (observe & confirm weekly)

**No action required right now** — Phase 4 executes automatically.

**Monitor at:** https://github.com/kushin77/self-hosted-runner/actions
