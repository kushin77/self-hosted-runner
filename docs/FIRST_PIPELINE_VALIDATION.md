# Validation & Verification — First Pipeline Execution

**Purpose:** Verify all GitLab CI automation is working hands-off after provisioning.  
**Timeline:** 10-15 min total
**Owner:** Ops (with engineering on standby for debugging)

---

## Step 1: Trigger First Validation Pipeline

Run from repo root or remotely:

```bash
export GITLAB_TOKEN="<YOUR_API_TOKEN>"
export CI_PROJECT_ID="<NUMERIC_PROJECT_ID>"
bash scripts/ops/trigger_first_pipeline.sh
```

**Expected output:**
```
✅ Pipeline triggered successfully
Pipeline ID: <ID>
Pipeline URL: https://gitlab.com/<namespace>/<project>/-/pipelines/<ID>
```

This triggers a new pipeline on `main` branch.

---

## Step 2: Wait for Validation Job

**In GitLab UI:** Project → CI/CD → Pipelines → Click latest pipeline

**Watch for:**
- ✅ `validate:ci` job appears (under "validate" stage)
- ⏳ Job runs for ~30 sec
- ✅ Job shows green checkmark (PASSED)

**What it does:**
- Checks `.gitlab-ci.yml` syntax (YAML validation)
- Verifies required 12 labels exist in project
- Optionally creates/closes test issue (skipped in CI with `SKIP_ISSUE_TEST=true`)

**If FAILED:** Check logs; likely cause is missing labels. Re-run Phase 1 provisioning:
```bash
PROJECT_ID=${CI_PROJECT_ID} GITLAB_TOKEN=${GITLAB_TOKEN} \
  bash scripts/gitlab-automation/create-required-labels-gitlab.sh
```

---

## Step 3: Manually Trigger Triage Job

**In GitLab UI, on the same pipeline:**

1. Find `triage:manual` job under "triage" stage
2. Click **Play** button (right side)
3. Job starts immediately

**Expected behavior (~1 min):**
- Fetches all open issues from project
- For unlabeled issues: adds `state:backlog` label
- For issues with security keywords (CVE, vulnerability, exploit): adds `type:security` and `priority:p0`
- For issues with no assignee: assigns to `ASSIGNEE_USERNAME` (if set in CI variables)
- Prints triage summary to logs

**Verify in GitLab UI:**
- Project → Issues → Check a few issues
- Unlabeled issues should now have `state:backlog` label
- Any security-related issues should have `type:security` + `priority:p0`

**If FAILED:** Check job logs for error. Common causes:
- `GITLAB_TOKEN` missing or invalid
- `CI_PROJECT_ID` mismatch
- Issues list API timeout (network issue)

---

## Step 4: Manually Trigger SLA Monitor Job

**In GitLab UI, on the same pipeline:**

1. Find `sla-monitor` job under "sla" stage
2. Click **Play** button (right side)
3. Job starts immediately

**Expected behavior (~1 min):**
- Fetches all open issues
- For each issue:
  - If `type:security` → SLA = 0.5 days (12 hours)
  - If `type:bug` + `severity:high` → SLA = 1 day
  - If `type:bug` + `severity:medium` → SLA = 3 days
  - If `type:compliance` → SLA = 1 day
- For breaches: adds `sla:breached` + `priority:urgent` labels
- Adds comment with breach details
- Generates JSONL log (audit trail)

**Verify in GitLab UI:**
- Project → Issues → Check labels
- Any old security/compliance issues should now have `sla:breached` label (if overdue)
- Click issue → Comments tab → should see SLA breach comment

**If no breaches found:** That's OK; it means no issues are overdue. The job is working correctly.

**If FAILED:** Check job logs. Common causes:
- `GITLAB_TOKEN` missing or invalid
- Label mismatch (verify labels match script expectations)
- API rate limiting (unlikely, but possible)

---

## Step 5: Verify Hands-Off Operation (Optional Schedules)

Once you've confirmed validate, triage, and SLA jobs work manually, enable schedules for continuous automation:

**Create Schedule 1: Auto-Triage (every 6 hours)**
- GitLab UI: Project → CI/CD → Schedules → **New schedule**
- Description: `Auto-triage issues (6h)`
- Cron: `0 */6 * * *`
- Branch: `main`
- Click **Save pipeline schedule**

**Or via CLI:**
```bash
PROJECT_ID=${CI_PROJECT_ID} GITLAB_TOKEN=${GITLAB_TOKEN} \
  bash scripts/gitlab-automation/create-schedule-gitlab.sh \
  "Auto-triage (6h)" "0 */6 * * *" main
```

**Create Schedule 2: SLA Monitor (every 4 hours)**
```bash
PROJECT_ID=${CI_PROJECT_ID} GITLAB_TOKEN=${GITLAB_TOKEN} \
  bash scripts/gitlab-automation/create-schedule-gitlab.sh \
  "SLA Monitor (4h)" "0 */4 * * *" main
```

**Verify schedules:**
- GitLab UI: Project → CI/CD → Schedules → should show 2 active schedules
- Cron times should show `0 */6 * * *` and `0 */4 * * *`

Once enabled, jobs run automatically without manual intervention.

---

## Verification Checklist

- [ ] Step 1: Pipeline triggered successfully
- [ ] Step 2: `validate:ci` job PASSED
- [ ] Step 3: `triage:manual` job PASSED (issues labeled)
- [ ] Step 4: `sla-monitor` job PASSED (or no breaches found)
- [ ] Step 5: Pipeline schedules created (optional, for hands-off operation)
- [ ] Issues in GitLab have expected labels (state:*, type:*, priority:*, sla:*)
- [ ] All jobs completed without errors

---

## Success Indicators

✅ **Validation Pipeline Passes**
- `.gitlab-ci.yml` is valid
- All 12 required labels exist

✅ **Triage Job Works**
- Unlabeled issues get `state:backlog`
- Security issues get `type:security` + `priority:p0`

✅ **SLA Job Works**
- Overdue issues get `sla:breached` + `priority:urgent`
- Comments added with breach details

✅ **Schedules Active (if enabled)**
- Triage runs every 6 hours automatically
- SLA monitor runs every 4 hours automatically
- Zero manual intervention required

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `validate:ci` FAILED | Labels missing | Re-run Phase 1 provisioning |
| `triage:manual` job runs but silent | No unlabeled issues | Check issue list; create test issue if needed |
| `triage:manual` ERROR: "401 Unauthorized" | Invalid token or permissions | Verify `GITLAB_TOKEN` has `api` scope |
| `sla-monitor` ERROR: "not found" | Label name mismatch | Run `create-required-labels-gitlab.sh` again |
| Pipeline triggers but no jobs appear | Runner offline | `ssh runner-host && sudo systemctl status gitlab-runner` |

---

## Metrics to Monitor

After first successful run, watch for:

| Metric | Expected | Frequency |
|--------|----------|-----------|
| Unlabeled issues reduced | Triage adds `state:backlog` | Every 6h (if schedule enabled) |
| SLA breaches detected | Issues get `sla:breached` label | Every 4h (if schedule enabled) |
| Job duration | <2 min per job | Per schedule |
| Error rate | 0% (runs should succeed) | Per job execution |
| Audit trail | GitLab comments + JSONL logs | Per job |

---

## Final Sign-Off

Once all steps pass:

```bash
git tag -a v1.0-gitlab-direct-deployment -m "First successful GitLab CI deployment with hands-off automation"
git push origin v1.0-gitlab-direct-deployment
```

Then close related GitHub issues:
- "GitLab Automation Migration - COMPLETE" (mark as done)
- "[REQUIRED] Ops Execution: GitLab CI Direct Deployment Activation" (mark as done)

---

## Next: Hands-Off Operation

Your infrastructure is now:
- ✅ **Immutable:** All changes tracked in Git + GitLab comments
- ✅ **Ephemeral:** Jobs create/run/cleanup (no leftover state)
- ✅ **Idempotent:** Schedules are safe to re-run
- ✅ **No-Ops:** Fully automated (triage 6h, SLA 4h)
- ✅ **Hands-Off:** Zero manual work after this validation
- ✅ **Direct Deployment:** Code commits to main, no PRs, no releases

Monitor via: GitLab UI → Project → CI/CD → Pipelines (view scheduled runs)
