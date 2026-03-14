# Cloud Scheduler: Weekly Vulnerability Scan Activation

**Status:** Ready for deployment  
**Date:** March 13, 2026  
**Project:** nexusshield-prod (GCP)

## Overview
Automate weekly vulnerability scans using Cloud Scheduler + Cloud Build. This guide provides step-by-step activation.

## Prerequisites
- GCP project: `nexusshield-prod`
- Cloud Scheduler API enabled
- Cloud Build API enabled
- Service account with `roles/cloudscheduler.jobRunner` permission

## Quick Start

### 1. Create Cloud Build Trigger (One-time setup)
Create a trigger named `VULN-SCAN-TRIGGER` that runs the repository vulnerability scan:

```bash
# Option A: Use Cloud Console
# Go to Cloud Build → Triggers → Create Trigger
# - Name: VULN-SCAN-TRIGGER
# - Source: GitHub (kushin77/self-hosted-runner)
# - Build config: Cloud Build (cloudbuild.yaml reference)
# - Add a build step: bash security/enhanced-secrets-scanner.sh repo-scan

# Option B: Using gcloud CLI
gcloud builds create \
  --name="VULN-SCAN-TRIGGER" \
  --project=nexusshield-prod \
  --source=https://github.com/kushin77/self-hosted-runner.git \
  --build="steps=[{name: 'gcr.io/cloud-builders/gke-deploy', args: ['--help']}]" \
  --substitutions="_SCAN_COMMAND=bash security/enhanced-secrets-scanner.sh repo-scan"
```

### 2. Create Cloud Scheduler Job

Once the trigger is created, run the activation script:

```bash
PROJECT=nexusshield-prod \
LOCATION=us-central1 \
SCHEDULE="0 3 * * 1" \
bash infra/cloud_scheduler/create_vuln_scan_job.sh
```

**Schedule breakdown:** `0 3 * * 1`
- `0 3` = 03:00 UTC
- `* * *` = Every day of month, every month, every day of week
- `1` = Monday

Adjust `SCHEDULE` cron expression as needed (see crontab format).

### 3. Verify Job Creation

```bash
# List all scheduler jobs
gcloud scheduler jobs list --location=us-central1 --project=nexusshield-prod

# Describe the vuln-scan job
gcloud scheduler jobs describe vuln-scan-weekly \
  --location=us-central1 \
  --project=nexusshield-prod

# View execution history
gcloud scheduler jobs describe vuln-scan-weekly \
  --location=us-central1 \
  --project=nexusshield-prod \
  --format="value(name,state,lastExecutionTime,lastAttemptTime)"
```

### 4. Test the Job

Manually trigger the job to verify it works:

```bash
gcloud scheduler jobs run vuln-scan-weekly \
  --location=us-central1 \
  --project=nexusshield-prod

# Monitor Cloud Build execution
gcloud builds list --project=nexusshield-prod | head -5
```

## Configuration

### Environment Variables
- `PROJECT`: GCP project ID (default: `nexusshield-prod`)
- `LOCATION`: Cloud Scheduler location (default: `us-central1`)
- `SCHEDULE`: Cron expression (default: `0 3 * * 1` = every Monday 3 AM UTC)
- `JOB_NAME`: Job display name (default: `vuln-scan-weekly`)

### Scan Command
The Cloud Build trigger should execute:
```bash
bash security/enhanced-secrets-scanner.sh repo-scan
```

This scans for:
- Secret patterns (API keys, credentials, JWT tokens)
- Dangerous file types (.key, .pem, .env files)
- Whitelisted paths (docs, examples, tests)

## Observability

### Cloud Logging
View scan results in Cloud Logging:

```bash
gcloud logging read \
  'resource.type=cloud_scheduler_job AND resource.labels.job_id=vuln-scan-weekly' \
  --project=nexusshield-prod \
  --limit=10 \
  --format=json
```

### Cloud Monitoring
Set up an alert if the job fails:

```bash
# Create an uptime check or alert policy in Cloud Monitoring console
# Alert condition: Cloud Scheduler job execution failure
# Notification channels: email, Slack, PagerDuty, etc.
```

## Troubleshooting

### Job doesn't run
- **Check permissions:** Service account needs `roles/cloudscheduler.jobRunner` and `roles/cloudbuild.builds.editor`
- **Check trigger:** Verify `VULN-SCAN-TRIGGER` exists and is enabled in Cloud Build
- **Check schedule:** Verify cron expression is correct (use `0 3 * * 1` for Monday 3 AM UTC)

### Scan fails
- **Check logs:** `gcloud builds log --stream <BUILD_ID> --project=nexusshield-prod`
- **Check connectivity:** Ensure Cloud Build can clone the GitHub repo (GitHub credentials in Secrets Manager)
- **Check scanner:** Verify `security/enhanced-secrets-scanner.sh` is executable and has no syntax errors

### Performance
- **Slow scans:** Large repositories may take > 5 min. Increase Cloud Scheduler timeout if needed.
- **High cost:** Cloud Build charges per build minute. Adjust schedule (e.g., monthly instead of weekly) if budget is a concern.

## Disabling the Job

```bash
# Disable without deleting
gcloud scheduler jobs pause vuln-scan-weekly \
  --location=us-central1 \
  --project=nexusshield-prod

# Delete the job
gcloud scheduler jobs delete vuln-scan-weekly \
  --location=us-central1 \
  --project=nexusshield-prod
```

## Next Steps
1. Create/verify the Cloud Build trigger in the Cloud Console
2. Run the helper script to create the scheduler job
3. Test the job manually once to confirm it works
4. Monitor first few runs to ensure stability

---
**Automation:** This guide is auto-generated. For updates, check the `infra/cloud_scheduler/` directory.
