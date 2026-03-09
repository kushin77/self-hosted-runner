# Automation Runbook — Hands-Off CI/CD Operations

**Status:** Fully Deployed & Idempotent  
**Last Updated:** 2026-03-07  
**Scope:** Immutable, ephemeral, idempotent automation for GitHub Actions workflow management, retry resilience, and artifact verification.

---

## Overview

This repository now includes **fully automated**, **hands-off** CI/CD operations with the following components:

1. **Retry Resilience** — Transient failures are automatically retried using an idempotent exponential-backoff wrapper.
2. **Self-Healing Runners** — Offline runners are detected and restarted (with Ansible/SSH key).
3. **Scheduled Watcher** — Runs every 10 minutes to detect failed runs and prepare bulk reruns.
4. **Auto-Merge Monitoring** — Draft issues with green checks are automatically merged when safe.
5. **Issue Auto-Close** — Admin issues requesting token provisioning are auto-closed once runners are healthy.

---

## Prerequisites for Hands-Off Operation

To enable **full hands-off automation**, add these secrets to the repository:

### Required Secrets

- **`RUNNER_MGMT_TOKEN`** (PAT)
  - Scopes: `administration:read` (to list runners and rerun workflows).
  - Used by: `admin-token-watch.yml` watcher workflow.
  - Purpose: Enables bulk reruns without manual intervention.

- **`DEPLOY_SSH_KEY`** (private key, PEM format)
  - Used by: `runner-self-heal.yml` → Ansible playbook for automated runner restart.
  - Purpose: Allows Ansible to SSH into runner hosts and restart services.
  - Example: `ssh-ed25519` private key or similar.

### Optional Secrets

- **`MINIO_ENDPOINT`**, **`MINIO_ACCESS_KEY`**, **`MINIO_SECRET_KEY`**
  - Purpose: Enables automated artifact verification from MinIO after reruns.
  - If provided, the watcher will check for artifacts and log findings.

---

## Automated Workflows & Scripts

### 1. **Runner Self-Heal** (`.github/workflows/runner-self-heal.yml`)

**Trigger:** Scheduled every 5 minutes + manual dispatch  
**Idempotency:** Uses concurrency group to prevent overlapping runs

**What it does:**
- Checks for offline runners via GitHub API.
- If offline runners found:
  - Attempts automated restart via Ansible (if `DEPLOY_SSH_KEY` present).
  - If no SSH key, creates an issue requesting manual intervention.
- If all runners healthy:
  - Auto-closes any open `RUNNER_MGMT_TOKEN` request issues to keep backlog clean.

**Logs:** `/tmp` (ephemeral per-run)  
**Issue Creation:** `label: runners,ops`

---

### 2. **Admin Token Watch** (`.github/workflows/admin-token-watch.yml`)

**Trigger:** Scheduled every 10 minutes + manual dispatch  
**Idempotency:** Reads from `/tmp`, logs results, does not duplicate reruns

**What it does:**
- Calls `scripts/automation/monitor_runs.sh` to find failed runs from the last 24 hours.
- Calls `scripts/automation/wait_and_rerun.sh` to attempt reruns.
- If `RUNNER_MGMT_TOKEN` is missing or insufficient:
  - Creates or updates a single urgent issue to alert admins.
  - Logs "found N failed, queued 0" to indicate the permission blockage.
- If `MINIO_*` secrets available:
  - Verifies artifacts were uploaded (optional, logged to `/tmp`).

**Logs:** `/tmp/failed_runs_*.txt`, `/tmp/rerun_results_*.txt`, `/tmp/minio_artifacts_*.txt`  
**Issue Label:** `automation,urgent,runners`

---

### 3. **Issue-Comment Auto-Rerun** (existing trigger in `admin-token-watch.yml`)

**Trigger:** Admin comments "grant" or "granted" on a matching issue.  
**Idempotency:** Issue comment is read once; subsequent reruns are handled by the schedule-based watcher.

**What it does:**
- Queues all failed runs for rerun when admin provides explicit approval.
- Posts a summary comment: "Automation: queued N reruns after admin grant."

---

### 4. **CI Retry Helper** (`scripts/automation/ci_retry.sh`)

**Used by:** `ts-check.yml`, `ci-images.yml`, reusable `terraform-apply-callable.yml`

**What it does:**
- Wraps shell commands with exponential backoff retry logic.
- Default: 3 attempts with 5-second initial delay.
- Idempotent: Each attempt is independent; no state carries over.

**Usage:**
```bash
./scripts/automation/ci_retry.sh 3 5 -- npm ci
./scripts/automation/ci_retry.sh 3 5 -- docker buildx build --push .
```

---

### 5. **Monitor & Watcher Scripts**

#### `scripts/automation/monitor_runs.sh`
- Fetches recent failed runs (default: last 24 hours).
- Outputs run IDs to `/tmp/failed_runs_<timestamp>.txt`.
- **Idempotent:** Each run produces a new timestamped file; no overwrites.

#### `scripts/automation/wait_and_rerun.sh`
- Reads the latest `failed_runs_*.txt` file.
- Attempts `gh run rerun` for each run ID.
- Logs results to `/tmp/rerun_results_<timestamp>.txt`.
- Optional: Checks MinIO for artifacts if credentials available.
- **Idempotent:** Subsequent runs produce new files; no duplicate actions.

#### `.github/scripts/auto_merge_pr_when_green.sh`
- Polls a PR until it's mergeable or merged.
- Attempts merge when safe.
- Exits when PR is already merged or closed.
- **Idempotent:** Safe to run repeatedly; no duplicate merges.

---

## Operational Workflow

### 1. **Initial Setup** (One-Time)

1. **Add secrets to repository:**
   ```bash
   gh secret set RUNNER_MGMT_TOKEN --repo kushin77/self-hosted-runner --body "$(cat /path/to/pat.txt)"
   gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner --body "$(cat ~/.ssh/id_ed25519)"
   ```

2. **Verify workflows enabled:**
   ```bash
   gh workflow list --repo kushin77/self-hosted-runner
   # Should show: runner-self-heal, admin-token-watch, etc.
   ```

3. **Monitor first runs:**
   ```bash
   gh run list --repo kushin77/self-hosted-runner --workflow runner-self-heal.yml --limit 5
   ```

---

### 2. **Continuous Operation** (Hands-Off)

**No manual intervention needed. The automation handles:**

- ✅ Retry failed runs every 10 minutes.
- ✅ Restart offline runners every 5 minutes.
- ✅ Close admin request issues when runners healthy.
- ✅ Reduce flakiness via retry wrapper on key steps.
- ✅ Auto-merge Draft issues with green checks (via scheduled merge script).

**Monitoring (optional):**
```bash
# Check recent watcher runs
gh run list --repo kushin77/self-hosted-runner --workflow admin-token-watch.yml --limit 10

# View logs of a specific run
gh run view <run-id> --repo kushin77/self-hosted-runner --log

# Search for permission errors
gh run view <run-id> --repo kushin77/self-hosted-runner --log | grep -i "403\|permission"
```

---

### 3. **Troubleshooting**

#### **Problem:** Runs are being queued but not executing.
- **Solution:** Check runner availability. The self-heal workflow will auto-restart offline runners.

#### **Problem:** Admin token watch says "queued 0".
- **Solution:** Ensure `RUNNER_MGMT_TOKEN` secret is set with `administration:read` scope. Verify via:
  ```bash
  gh secret list --repo kushin77/self-hosted-runner | grep RUNNER_MGMT_TOKEN
  ```

#### **Problem:** MinIO artifacts not verified.
- **Solution:** Optional feature. If `MINIO_*` secrets not set, artifact verification is skipped. To enable, add secrets and the watcher will verify on next run.

#### **Problem:** An admin issue keeps being created.
- **Solution:** This means the watcher detected missing/insufficient permissions. Add the missing secrets (see Prerequisites section).

---

### 4. **Monitoring & Logs**

**Watcher Output (ephemeral, cleared after 7 days):**
```
/tmp/failed_runs_<TS>.txt          # List of failed run IDs
/tmp/rerun_results_<TS>.txt        # Rerun attempt summary
/tmp/monitor_runs_<TS>.txt         # Monitor script output
/tmp/minio_artifacts_<TS>.txt      # MinIO artifact verification (if available)
```

**View latest logs:**
```bash
ls -tlr /tmp/{failed_runs,rerun_results,monitor_runs,minio_artifacts}*.txt | tail -5
cat /tmp/rerun_results_$(date +%Y%m%d)*.txt | tail -20 # Today's summary
```

---

## Issue Lifecycle (Automated)

### Triage Issues
- **Label:** `automation,blocker` or `automation,triage`
- **Lifecycle:** Created by watcher when failures detected → Closed when automation resolves them.
- **Auto-Close Trigger:** If a failed run is rerun and succeeds, the blocker issue is closed automatically.

### Admin Issues
- **Label:** `automation,urgent,runners`
- **Lifecycle:** Created when `RUNNER_MGMT_TOKEN` missing → Updated every 10 min with reminder → Closed when runners healthy.
- **Auto-Close Trigger:** `runner-self-heal.yml` closes these when `offline_count == 0`.

---

## Performance & Overhead

- **CPU:** Minimal — watcher scripts are I/O-bound (API calls, no heavy compute).
- **API Quota:** Low — one `/repos/<repo>/actions/runners` call per 10 min + one `gh run rerun` per failed run.
- **Artifact Storage:** MinIO verification is optional; if enabled, uses negligible bandwidth.

---

## Immutability & Idempotency Guarantees

✅ **Immutable:** All scripts and workflows are version-controlled in `.github/workflows/` and `scripts/automation/`.  
✅ **Ephemeral:** Logs and temp files written to `/tmp` are cleared periodically; no persistent state.  
✅ **Idempotent:** Multiple runs of the same watcher produce new timestamped files and do not duplicate actions:
- If a run is already queued, `gh run rerun` returns an error and is logged.
- If a PR is already merged, the merge script exits cleanly.
- If an admin issue already exists, it is updated (not duplicated) with a new comment.

---

## Scaling & Customization

### Adjust Retry Parameters
Edit `scripts/automation/ci_retry.sh`:
```bash
MAX_ATTEMPTS=${1:-3}  # Change default attempts
INITIAL_DELAY=${2:-5} # Change initial delay (seconds)
```

### Adjust Watcher Frequency
Edit `.github/workflows/admin-token-watch.yml`:
```yaml
schedule:
  - cron: '*/10 * * * *'  # Every 10 min; change to '*/5' for every 5 min
```

### Adjust Runner Self-Heal Frequency
Edit `.github/workflows/runner-self-heal.yml`:
```yaml
schedule:
  - cron: '*/5 * * * *'  # Every 5 min; adjust as needed
```

---

## Emergency Procedures

### **To Pause Automation Temporarily**

Disable workflows via GitHub UI or CLI:
```bash
gh workflow disable --repo kushin77/self-hosted-runner admin-token-watch.yml
gh workflow disable --repo kushin77/self-hosted-runner runner-self-heal.yml
```

### **To Resume Automation**

```bash
gh workflow enable --repo kushin77/self-hosted-runner admin-token-watch.yml
gh workflow enable --repo kushin77/self-hosted-runner runner-self-heal.yml
```

### **To Manually Trigger a Watcher Run**

```bash
gh workflow run admin-token-watch.yml --repo kushin77/self-hosted-runner
gh workflow run runner-self-heal.yml --repo kushin77/self-hosted-runner
```

---

## Success Criteria

- [ ] `RUNNER_MGMT_TOKEN` and `DEPLOY_SSH_KEY` secrets provisioned.
- [ ] Watcher workflow runs every 10 minutes without auth errors.
- [ ] Failed runs are requeued automatically.
- [ ] Offline runners are restarted via Ansible within 5 minutes.
- [ ] Admin issues auto-close when runners healthy.
- [ ] No manual intervention required beyond the initial secret provisioning.

---

## Support & Issues

- **Automations Not Running?** Check workflow status: `gh workflow list --repo kushin77/self-hosted-runner`
- **Permission Errors?** Verify secrets: `gh secret list --repo kushin77/self-hosted-runner`
- **Need to Adjust Schedules?** Edit cron expressions in workflow files and PR the changes.

---

**Document Version:** 1.0  
**Maintained By:** Automation Agent  
**Last Run Success:** (Check latest workflow run)
