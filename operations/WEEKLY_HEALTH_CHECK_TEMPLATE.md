# Weekly Health Check Template — Enterprise Best Practices Edition

**Purpose:** Structured 30-minute operational health review with verification, risk assessment, and compliance validation.

**Owner:** `__ops-lead__` (escalate to CTO if health score < 95%)  
**Frequency:** Monday 9:00 AM UTC (weekly)  
**Duration:** 30 minutes  
**Success Criteria:** Health score ≥ 95%, zero high-severity incidents, all phases green

---

## PRE-CHECK (2 min) — Setup & Baseline

- [ ] **Access Verification:** Verified access to all monitoring dashboards (Prometheus, Cloud Monitoring, GitLab)
- [ ] **Baseline Capture:** Recorded current metrics (triage job count, SLA breaches, runner uptime)
- [ ] **Incident Context:** Reviewed incident log from last 7 days (any patterns?)

**Risk Assessment Starting State:**
```
Service Health:  [ ] Green  [ ] Amber  [ ] Red  (start here)
Incident Count:  _____ (target: 0)
Escalations:     _____ (target: 0)
```

---

## PHASE 1: Automation & Workflows (5 min)

**GitLab CI Pipeline Health:**
- [ ] Triage job (every 6h): Latest run ✓ / ✗ / ⏳ (status: ____)
- [ ] SLA Monitor job (every 4h): Latest run ✓ / ✗ / ⏳ (status: ____)
- [ ] Bootstrap job (manual): Last successful run: ____ (when?)
- [ ] Schedule jobs enabled: Yes ✓ / No ✗

**Verification Command:**
```bash
# Check last 10 pipeline runs
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/$CI_PROJECT_ID/pipelines?per_page=10" | \
  jq '.[] | {id, status, updated_at}'
```

**Metrics to Log:**
- Total pipeline runs this week: _____
- Success rate: _____%
- Avg execution time: _____ sec

---

## PHASE 2: Secrets & Credentials (5 min)

**Multi-Layer Secret Management Validation:**
- [ ] **GSM Health:** Last rotation timestamp: ____, Status: ✓ / ✗
  - Verify: `gcloud secrets versions list github-token --limit=1`
- [ ] **Vault Health:** Last rotation timestamp: ____, Status: ✓ / ✗
  - Verify: `curl -s $VAULT_ENDPOINT/v1/auth/token/lookup-self | jq '.data.ttl'`
- [ ] **AWS KMS Health:** Last rotation timestamp: ____, Status: ✓ / ✗
  - Verify: `aws secretsmanager describe-secret --secret-id github-pat`

**OIDC Token Validation:**
- [ ] GitHub → AWS: OIDC provider active ✓ / ✗
- [ ] GitHub → GCP: Workload Identity working ✓ / ✗
- [ ] Token generation test passed: ✓ / ✗

**Risk Flag:** Any secrets rotated more than 7 days ago? ❌ YES (escalate) / ✅ NO

---

## PHASE 3: Runner & Infrastructure (5 min)

**GitLab Runner Status:**
- [ ] Runner registered: Yes ✓ / No ✗
- [ ] Runner online: Yes ✓ / No ✗ (via GitLab UI → Runners page)
- [ ] Tags verified: `automation`, `primary` present ✓ / ✗
- [ ] Host resource utilization: CPU ____%, Memory ____%, Disk ____%

**Verification Command:**
```bash
sudo gitlab-runner verify
sudo gitlab-runner status
# Check host metrics:
free -h && df -h / && top -bn1 | head -20
```

**Performance Baseline:**
- Job success rate: ____% (target: ≥99%)
- Avg job duration: _____ sec (last 5 jobs)
- Failed jobs: ____ (target: 0)

**Risk Flag:** Any resource > 85%? ❌ YES (alert) / ✅ NO

---

## PHASE 4: Issue Triage & SLA Compliance (5 min)

**Triage Automation Validation:**
- [ ] Issues labeled this week: ____ (target: 100% < 24h after creation)
- [ ] Security issues escalated: ____ (target: 100% escalated within 2h)
- [ ] Average time-to-label: _____ min (target: <15 min)

**SLA Breach Detection:**
- [ ] P0 breached: ____ (target: 0) — **Escalate immediately if >0**
- [ ] P1 breached: ____ (target: <1)
- [ ] P2 breached: ____ (target: <5)

**Verification Command:**
```bash
# Check issues created last 7 days (should all be labeled)
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/$CI_PROJECT_ID/issues?created_after=$(date -d '7 days ago' -Iseconds)" | \
  jq '.[] | {id, title, labels, created_at}'
```

**Metrics to Log:**
- Total unlabeled issues: ____ (target: 0)
- Average label latency: _____ min

---

## PHASE 5: Compliance & Security (3 min)

**Audit Trail Verification:**
- [ ] JSONL logs append-only: ✓ / ✗ (check: `wc -l` unchanged from last week)
- [ ] GitHub PR comments immutable: ✓ / ✗ (spot-check 2-3 PRs)
- [ ] Git history signed: ✓ / ✗ (check: `git log --show-signature | head`)
- [ ] No credentials in repo: ✓ / ✗ (run: `bash scripts/verify-no-secrets.sh`)

**Compliance Gaps:**
- Security policies violated: ❌ YES (describe: ____) / ✅ NO
- Documentation stale: ❌ YES (files: ____) / ✅ NO
- Access controls changed: ❌ YES (describe: ____) / ✅ NO

---

## PHASE 6: Health Score Calculation (2 min)

**Scoring Matrix:**

| Component | Weight | Status | Score |
|---|---|---|---|
| Pipeline Success | 25% | ✓/✗ | __/25 |
| Secret Rotation | 20% | ✓/✗ | __/20 |
| Runner Health | 20% | ✓/✗ | __/20 |
| Triage SLA | 20% | ✓/✗ | __/20 |
| Compliance | 15% | ✓/✗ | __/15 |
| **TOTAL** | **100%** | | **__/100** |

**Health Score:** _____ (target: ≥95%)

**Pass/Fail Decision:**
```
✅ GREEN  (95-100)  → All checks passing, proceed normally
🟡 AMBER  (85-94)   → Fix identified issues before Friday
🔴 RED    (<85)     → Escalate to CTO immediately
```

---

## ESCALATION PROCEDURES

### If Health Score < 95%

**Immediate Actions:**
1. **Document Finding:** Describe issue in "Summary & Findings" section below
2. **Assign Owner:** Set deadline (EOD? EOW? Next sprint?)
3. **Notify Team:** Post to `#ops-weekly` with health score + action items
4. **CTO Alert:** If score < 85%, notify CTO + schedule emergency meeting

**Example Escalation:**
```
🔴 HEALTH SCORE: 82/100 ❌ ESCALATED TO CTO

Issue: SLA Monitor job failing (last 3 runs failed)
Root Cause: GitLab API rate limit (429 responses)
Action: Add exponential backoff to sla-monitor-gitlab.sh
Timeline: Fix by EOD today (owner: @ops-lead)
Impact: High (SLA breaches undetected for 12h)
```

---

## FINDINGS & ACTIONS

**Week of:** ____ (Monday date)  
**Health Score:** ____ / 100  
**Status:** ✅ GREEN / 🟡 AMBER / 🔴 RED

### Summary of Findings
```
(Observations from all 5 phases)
- _________________________________
- _________________________________
- _________________________________
```

### Incident Log (if any)
```
Incident 1: _________________ | Severity: P0/P1/P2 | Status: Open/Resolved
  Root Cause: ____________________
  Resolution: ____________________
  Timeline: Started ____, Resolved ____
```

### Action Items
| Item | Owner | Priority | Deadline | Status |
|---|---|---|---|---|
| Rotate secrets (GSM→Vault→KMS) | @ops-lead | P0 | EOD Thu | ⏳ In Progress |
| Update triage script (rate limit fix) | @dev-team | P0 | EOW | ⏳ In Progress |
| Audit OIDC token TTLs | @security | P1 | EOW | ⏳ Not Started |

---

## DOCUMENTATION & KNOWLEDGE BASE

**Quick Reference:**
- Pipeline Runbook: `docs/HANDS_OFF_AUTOMATION_RUNBOOK.md`
- Troubleshooting: `BEST_PRACTICES_CLOSURE_20260312.md` → Troubleshooting section
- Emergency Procedures: See `docs/INCIDENT_RESPONSE_PLAYBOOK.md`

**For Future Weeks:**
- Baseline metrics (for trending): [See baseline log](#baseline-metrics)
- Known issues: [See incident tracking](#incident-tracking)
- Standing action items: [See recurring tasks](#recurring-tasks)

---

## POST-CHECK (2 min) — Sign-Off

**Verification:**
- [ ] All sections completed
- [ ] Health score calculated
- [ ] Action items assigned
- [ ] Slack notification sent to `#ops-weekly`
- [ ] Log archived (filename: `WEEKLY_HEALTH_CHECK_2026-03-03.md` format)

**Sign-Off:**
```
Conducted By: _________________ (name)
Date: _________________ (YYYY-MM-DD)
Duration: _____ minutes (target: 30)
Confidence Level: 🟢 HIGH / 🟡 MEDIUM / 🔴 LOW
Next Review: _________________ (date, ~7 days)
```

**Notification Template** (for Slack #ops-weekly):
```
📊 WEEKLY HEALTH CHECK COMPLETE

Health Score: 🟢 __/100 (__%)
Status: ✅ GREEN / 🟡 AMBER / 🔴 RED

Key Metrics:
  • Pipeline success rate: ____%
  • SLA breaches: ____
  • Runner uptime: ____%
  • Secrets rotation: All current ✓

Action Items: ____ (see details below)
[Details: ...]

Conducted: @ops-lead | Duration: 30 min
```

---

## APPENDIX: Baseline Metrics (Track Weekly)

| Week | Pipeline Success | SLA Breaches | Runner Uptime | Health Score |
|---|---|---|---|---|
| 2026-03-03 | ___% | __ | ___% | __/100 |
| 2026-03-10 | ___% | __ | ___% | __/100 |
| 2026-03-17 | ___% | __ | ___% | __/100 |

**Trend Analysis:** (Fill after 3+ weeks of data)
```
Pipeline Success: ↗️ Improving / → Stable / ↘️ Degrading
SLA Breaches: ↗️ Increasing / → Stable / ↘️ Decreasing (good!)
```

---

**Last Updated:** 2026-03-12  
**Maintained By:** Infrastructure/Platform Team  
**Review Frequency:** Monthly (update template if process changes)
