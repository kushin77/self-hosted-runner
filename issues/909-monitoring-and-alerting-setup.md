Title: Monitoring & Alerting Setup (Hands-Off Pipeline Observability)

Goal: Set up monitoring for the DR pipeline to ensure alerts are triggered on failures, metric thresholds are exceeded, or backups become stale.

Status: Ready for Ops

Preconditions:
- Issues 906, 907, 908 have been completed (credentials provisioned, keys rotated, backups verified).
- GitLab API token and github-token are in GSM.
- Slack webhook is configured in GSM (for notifications).

What This Issue Does:
- Enables continuous monitoring of the quarterly DR dry-run pipeline
- Sends Slack alerts if RTO/RPO thresholds are exceeded
- Monitors backup freshness and integrity
- Exports metrics for observability and trending

Checklist:

**1. Verify CI Templates Are Wired:**
- [ ] Confirm `ci_templates/dr-alert.yml` exists locally: `ls -la ci_templates/dr-alert.yml`
- [ ] Verify `.gitlab-ci.yml` includes the template:
  ```bash
  grep "ci_templates/dr-alert.yml" config/cicd/.gitlab-ci.yml
  ```
- [ ] Commit any changes to main if not already done:
  ```bash
  git add config/cicd/.gitlab-ci.yml ci_templates/dr-alert.yml scripts/ci/dr_pipeline_monitor.sh
  git commit -m "feat(dr): add monitoring & alerting pipeline templates"
  git push origin main
  ```

**2. Configure Slack Alerts (Already in Place):**
- [ ] Verify slack-webhook secret exists in GSM:
  ```bash
  gcloud secrets versions access latest --secret=slack-webhook --project=gcp-eiq | wc -c
  ```
- [ ] The monitoring script automatically posts alerts to Slack on:
  - Pipeline failure
  - RTO exceeds 60 minutes
  - RPO exceeds 30 minutes
  - Monitoring timeout
  - Backup freshness issues

**3. Test Monitoring Script (Optional but Recommended):**
- [ ] Run monitoring script locally (dry-run):
  ```bash
  export SECRET_PROJECT=gcp-eiq
  export GITLAB_PROJECT_ID="<YOUR_PROJECT_ID>"
  ./scripts/ci/dr_pipeline_monitor.sh --poll-interval 5 --timeout 60
  ```
  (Expect: Script queries GitLab API, checks mirror repo & backup bucket, posts summary to Slack)

**4. Verify Metrics Export:**
- [ ] After the next scheduled DR dry-run, check that metrics are exported:
  ```bash
  # In the GitLab pipeline job artifacts, look for metrics.env containing:
  # DR_RTO, DR_RPO, DR_PIPELINE_ID, DR_RUN_TIMESTAMP
  ```
- [ ] Metrics are stored as GitLab CI variables and can be queried via API:
  ```bash
  curl -H "PRIVATE-TOKEN: $GITLAB_API_TOKEN" \
    https://gitlab.com/api/v4/projects/<PROJECT_ID>/variables | jq '.[] | select(.key | startswith("DR_"))'
  ```

**5. Set Up Optional Custom Thresholds (Advanced):**
- [ ] To customize RTO/RPO alert thresholds, update `ci_templates/dr-alert.yml`:
  ```yaml
  variables:
    RTO_THRESHOLD: "45"  # Alert if RTO > 45 minutes (default: 60)
    RPO_THRESHOLD: "20"  # Alert if RPO > 20 minutes (default: 30)
  ```
- [ ] Commit the changes

**6. Monitor the Next Scheduled Dry-Run:**
- [ ] Wait for the next quarterly schedule trigger (or trigger manually via GitLab UI: CI/CD → Schedules → "DR dry-run quarterly schedule" → click "Play")
- [ ] Watch for Slack notifications in your configured channel (default: `#dr-automation`)
- [ ] Verify monitoring job completes successfully in the GitLab pipeline

**7. Audit & Close:**
- [ ] Confirm monitoring logs are stored in pipeline artifacts:
  ```bash
  # In GitLab: Pipelines > [Pipeline ID] > Artifacts > monitoring.log
  ```
- [ ] Verify at least one successful alert notification was posted to Slack
- [ ] Close this issue once monitoring is active and alerts are confirmed working

Reference:
- Monitoring Script: `scripts/ci/dr_pipeline_monitor.sh`
- Alert Templates: `ci_templates/dr-alert.yml`
- DR Runbook: `docs/DR_RUNBOOK.md`
- OPS Finalization Runbook: `docs/OPS_FINALIZATION_RUNBOOK.md`

**What Happens After This Issue Is Closed:**
The system is **fully hands-off and observable**:
- Quarterly DR dry-run runs on schedule (created in issue 906)
- Pipeline monitors for success/failure (this issue)
- Alerts posted automatically to Slack on issues
- Metrics (RTO/RPO) exported and available for trending
- No manual monitoring or alerting needed

Notes:
- This issue is a **non-blocking enhancement** (the DR system works without active monitoring, but monitoring is strongly recommended for production use).
- All scripts are idempotent and can be re-run or adjusted without side effects.
- To disable alerting, simply set `only:` to `[]` in the GitLab job definition.
