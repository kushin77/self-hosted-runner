# Hands-Off Automation Runbook: GitLab Direct Deployment

## Status
✅ **IMPLEMENTATION COMPLETE** — Ready for Ops Provisioning & Host Migration

**Date:** 2026-03-12  
**Deployment Model:** Direct-to-main, no PRs, no releases, fully automated, hands-off  
**CI/CD Engine:** GitLab CI (GitHub Actions removed)  
**Secret Management:** GSM/VAULT/KMS (credentials externalized)

---

## Phase 1: Provisioning (Ops Task)

### Prerequisites
- [ ] GitLab project created and accessible
- [ ] GitLab access token with `api` scope (store in secure vault)
- [ ] Project ID (numeric, from GitLab UI or `curl -s https://gitlab.com/api/v4/projects/<namespace>%2F<project>`)

### Step 1.1: Add CI Variables
**Location:** GitLab UI → Project → Settings → CI/CD → Variables

Create these as **masked** and **protected**:
```
GITLAB_TOKEN          = <your-api-token>
CI_PROJECT_ID         = <numeric-project-id>
ASSIGNEE_USERNAME     = <your-gitlab-username>
GITLAB_API_URL        = https://gitlab.com/api/v4
```

Or execute script:
```bash
export GITLAB_TOKEN="<token>"
export CI_PROJECT_ID="<id>"
export GITLAB_API_URL="https://gitlab.com/api/v4"

bash scripts/gitlab-automation/create-ci-variables-gitlab.sh
```

**Verify:**
```bash
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API_URL/projects/$CI_PROJECT_ID/variables" | jq '.[] | {key, value_type}'
```

### Step 1.2: Provision Required Labels
**Trigger** one of:

**Option A: Manual execution:**
```bash
export GITLAB_TOKEN="<token>"
export CI_PROJECT_ID="<id>"
export GITLAB_API_URL="https://gitlab.com/api/v4"

bash scripts/gitlab-automation/create-required-labels-gitlab.sh
```

**Option B: Trigger GitLab CI bootstrap job:**
1. Go to GitLab UI → Project → CI/CD → Pipelines
2. Click **Run pipeline** on `main` branch
3. Under **Variables**, add `CI_PROJECT_ID` and `GITLAB_TOKEN` (if not already in CI/CD settings)
4. In pipeline, manually trigger `bootstrap:provision` job

**Verify:**
```bash
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API_URL/projects/$CI_PROJECT_ID/labels" | jq '.[] | .name' | sort
```

Expected labels (12 total):
```
priority:p0, priority:p1, priority:p2, priority:p3
severity:critical, severity:high, severity:medium, severity:low
state:backlog, state:in_progress, state:review, state:done
type:security, type:bug, type:feature, type:documentation
sla:breached, sla:escalated
(plus color assignments per script)
```

### Step 1.3: Enable Pipeline Schedules (Optional but Recommended)
**Location:** GitLab UI → Project → CI/CD → Schedules

Create schedules for hands-off automation:

| Job | Cron | Purpose |
|-----|------|---------|
| `sla:monitor` | `0 */4 * * *` | Check SLA breaches every 4 hours |
| `triage:auto` | `0 */6 * * *` | Auto-triage unlabeled issues every 6 hours |

Or use script:
```bash
export GITLAB_TOKEN="<token>"
export CI_PROJECT_ID="<id>"
export GITLAB_API_URL="https://gitlab.com/api/v4"

bash scripts/gitlab-automation/create-schedule-gitlab.sh \
  "SLA Monitor (4h)" "0 */4 * * *" main
```

---

## Phase 2: Host Runner Migration (Infrastructure Task)

### Prerequisites
- [ ] SSH access to self-hosted-runner host
- [ ] Host has Ubuntu 20.04+ or compatible Linux
- [ ] Root or `sudo` access on host
- [ ] GitLab Runner registration token (from Project → Settings → CI/CD → Runners)

### Step 2.1: Backup Current State
```bash
# On host
cd /home/akushnir/self-hosted-runner
git status
git log --oneline -1

# Backup repo if needed
cp -r . /backup/self-hosted-runner-$(date +%Y%m%d-%H%M%S)
```

### Step 2.2: Stop GitHub Actions Runner
```bash
# Stop service
sudo systemctl stop actions-runner

# Disable auto-start (optional)
sudo systemctl disable actions-runner
```

### Step 2.3: Install GitLab Runner
```bash
# Download and install
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# Verify
gitlab-runner --version
```

### Step 2.4: Register GitLab Runner
```bash
sudo gitlab-runner register \
  --url https://gitlab.com/ \
  --registration-token "<your-registration-token>" \
  --executor shell \
  --description "self-hosted-runner" \
  --run-untagged false \
  --tag-list "automation,primary" \
  --maintenance-note "Direct deployment runner" \
  --locked false
```

**Interactive Registration (if preferred):**
```bash
sudo gitlab-runner register
# When prompted:
# GitLab instance URL: https://gitlab.com/
# Registration token: <paste-token>
# Runner description: self-hosted-runner
# Runner tags: automation,primary
# Executor: shell
```

### Step 2.5: Start GitLab Runner
```bash
sudo systemctl start gitlab-runner
sudo systemctl enable gitlab-runner

# Verify
sudo systemctl status gitlab-runner
sudo gitlab-runner verify
```

### Step 2.6: Verify Runner Registration
**In GitLab UI:**
- Go to Project → Settings → CI/CD → Runners
- Confirm runner appears as "online" (green dot)
- Tags should show: `automation`, `primary`

**Or test via CLI:**
```bash
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API_URL/projects/$CI_PROJECT_ID/runners" | jq '.[] | {id, description, status, tag_list}'
```

---

## Phase 3: Validation & Activation

### Step 3.1: Trigger Validation Pipeline
**Option A: Push test commit:**
```bash
cd /home/akushnir/self-hosted-runner
git commit --allow-empty -m "test: trigger GitLab CI validation pipeline"
git push origin main
```

**Option B: Manually trigger from UI:**
1. Go to GitLab UI → Project → CI/CD → Pipelines
2. Click **Run pipeline** on `main`
3. Confirm `validate` job starts and passes

### Step 3.2: Verify Validation Pipeline
Expected output:
```
✅ validate:schema        PASSED  (checks .gitlab-ci.yml syntax)
✅ validate:labels_exist  PASSED  (confirms required labels exist)
✅ validate:test_issue    SKIPPED (runs only with SKIP_ISSUE_TEST=false)
```

**Check logs:**
```bash
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API_URL/projects/$CI_PROJECT_ID/pipelines" | jq '.[0] | {id, status, web_url}'
```

### Step 3.3: Test Triage Job (Manual Trigger)
```bash
curl -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "$GITLAB_API_URL/projects/$CI_PROJECT_ID/pipelines" \
  -d '{"ref":"main"}' | jq '.id'

# Then visit pipeline in UI and manually trigger triage:auto
```

Expected: Issues without labels get `state:backlog` label, security issues get escalated.

### Step 3.4: Test SLA Monitor (Manual Trigger)
Same as triage above. Expected: SLA breachers get `sla:breached` + `priority:urgent` labels.

---

## Phase 4: Hands-Off Production Operation

### Fully Automated Workflows (Post-Provisioning)

| Trigger | Job | Frequency | Action |
|---------|-----|-----------|--------|
| Scheduled | `sla:monitor` | Every 4 hours | Check SLA breaches, escalate with labels |
| Scheduled | `triage:auto` | Every 6 hours | Label unlabeled issues, escalate security |
| Direct commit | `validate` | On push | Validate pipeline schema and labels |
| Manual | `bootstrap:provision` | On-demand | Recreate labels & CI variables (idempotent) |

### Zero Manual Intervention Required For:
- ✅ Issue labeling (auto-triage)
- ✅ SLA breach detection (auto-escalation)
- ✅ Security issue escalation (auto-priority)
- ✅ Pipeline validation (pre-commit)
- ✅ Credential rotation (GSM/VAULT/KMS scheduled separately)

### Monitoring Dashboard (Optional)
GitLab UI → Project → Monitor → Error Tracking / Incidents

View all pipeline executions and job logs.

---

## Phase 5: Secret Management Integration

### GSM (Google Secret Manager) Setup
```bash
# Store credentials in GSM
gcloud secrets create GITLAB_TOKEN --data-file=- <<< "$GITLAB_TOKEN"
gcloud secrets create CI_PROJECT_ID --data-file=- <<< "$CI_PROJECT_ID"

# Runner will fetch at job start via environment setup
```

### VAULT (HashiCorp Vault) Setup
```bash
vault kv put secret/gitlab \
  token="$GITLAB_TOKEN" \
  project_id="$CI_PROJECT_ID"

# Runner fetches via vault login + kv get
```

### KMS (AWS Key Management Service) Setup
```bash
# Encrypt secrets
aws kms encrypt --key-id <key-id> --plaintext "$GITLAB_TOKEN" \
  --output text --query CiphertextBlob > gitlab_token.enc

# Runner decrypts: aws kms decrypt --ciphertext-blob fileb://gitlab_token.enc
```

**In `.gitlab-ci.yml`, use `before_script` to fetch and export:**
```yaml
before_script:
  - export GITLAB_TOKEN=$(gcloud secrets versions access latest --secret GITLAB_TOKEN)
  - export CI_PROJECT_ID=$(gcloud secrets versions access latest --secret CI_PROJECT_ID)
```

---

## Phase 6: Direct Deployment Model

### Development Workflow
```bash
# 1. Make changes locally
git add .
git commit -m "feat: add new capability (direct-to-main)"

# 2. Push directly to main (no PR required)
git push origin main

# 3. GitLab CI validates automatically
# 4. Scheduled jobs auto-triage and monitor SLA
# 5. No releases: deployment happens via separate CD system
```

### Deployment Hooks (Optional)
If you need release/deployment triggers on git events, create custom webhooks:

**Webhook URL:** GitLab UI → Project → Settings → Webhooks

Example payload sends to your deployment system on:
- Tag push (for release builds)
- Main branch push (for continuous deployment)

**No GitHub Actions. No PR workflow. Pure GitLab CI.**

---

## Rollback Plan

If issues occur during validation:

### Quick Rollback (Revert to GitHub Actions)
```bash
# Find pre-deletion commit
git log --oneline | grep "GitHub Actions"

# Revert
git revert <commit-hash>
git push origin main

# Or restore workflows from git history
git checkout <pre-deletion-commit> -- .github/workflows/
git commit -m "rollback: restore GitHub Actions workflows"
git push origin main
```

### Quick Rollback (Revert to GitHub Runner)
```bash
# On host
sudo systemctl stop gitlab-runner
sudo systemctl disable gitlab-runner

sudo systemctl start actions-runner
sudo systemctl enable actions-runner
```

---

## Troubleshooting

### Issue: `bootstrap:provision` job fails
**Cause:** CI variables not set or token invalid  
**Fix:**
1. Confirm `GITLAB_TOKEN` and `CI_PROJECT_ID` in Settings → CI/CD → Variables
2. Test token: `curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.com/api/v4/user`

### Issue: Labels don't exist after bootstrap
**Cause:** Script ran but didn't create labels (idempotency check)  
**Fix:** Manually run helper script with debug output:
```bash
bash -x scripts/gitlab-automation/create-required-labels-gitlab.sh
```

### Issue: Triage job labels issues with wrong labels
**Cause:** Label names don't match expected taxonomy  
**Fix:** Verify labels match script expectations in `create-required-labels-gitlab.sh`

### Issue: Runner marked offline
**Cause:** Service stopped or network issue  
**Fix:**
```bash
sudo systemctl restart gitlab-runner
sudo gitlab-runner verify --delete
sudo gitlab-runner register # (register again if needed)
```

---

## Success Criteria

✅ **Phase 1 Complete:**
- [ ] CI variables created and visible in Settings
- [ ] Required 12+ labels exist in project
- [ ] Pipeline schedules created (SLA, triage)

✅ **Phase 2 Complete:**
- [ ] GitHub Actions runner service stopped
- [ ] GitLab Runner installed and registered
- [ ] Runner appears "online" in Settings → Runners

✅ **Phase 3 Complete:**
- [ ] Validation pipeline passes
- [ ] Triage job labels unlabeled issues
- [ ] SLA monitor detects breaches (if any)

✅ **Phase 4 Complete:**
- [ ] First scheduled job runs automatically
- [ ] No manual interventions required
- [ ] Issues auto-labeled and escalated per policy

✅ **Phase 5 Complete (if using secrets):**
- [ ] Credentials stored in GSM/VAULT/KMS
- [ ] Runner fetches secrets at job start
- [ ] No secrets visible in logs or repo

✅ **Phase 6 Complete:**
- [ ] Direct commits to `main` work (no PR required)
- [ ] All automation runs hands-off
- [ ] Audit trail maintained (GitLab issues + comments)

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `.gitlab-ci.yml` | Main GitLab CI pipeline definition |
| `scripts/gitlab-automation/*.sh` | Helper scripts for provisioning and monitoring |
| `docs/GITLAB_RUNNER_MIGRATION.md` | Detailed host migration steps |
| `docs/GITLAB_CI_SETUP.md` | CI variables, runner config, schedules |
| `docs/MR_CHECKLIST.md` | Pre-merge review checklist |
| `docs/MR_FINAL_INSTRUCTIONS.md` | Post-merge provisioning steps |

---

## Support & Escalation

**Questions on GitLab CI config?**  
→ See `.gitlab-ci.yml` comments and `docs/GITLAB_CI_SETUP.md`

**Questions on scripts?**  
→ See `scripts/gitlab-automation/README.md` or run with `-x` flag for debug output

**Issues with runner registration?**  
→ See Phase 2 or run `sudo gitlab-runner verify`

**Need to disable automation?**  
→ Edit `.gitlab-ci.yml`, set all schedules to disabled, or remove runner from project

---

**Last Updated:** 2026-03-12  
**Status:** ✅ READY FOR OPS PROVISIONING  
**Phase:** Direct Deployment Activation
