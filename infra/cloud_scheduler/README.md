# Weekly Vulnerability Scan (Cloud Scheduler)

This folder contains helper artifacts to schedule a weekly vulnerability scan using Cloud Scheduler + Cloud Build.

Usage:

1. Create a Cloud Build trigger named `VULN-SCAN-TRIGGER` in project `nexusshield-prod` that runs the vulnerability scan build (for example, a build step that runs `bash security/enhanced-secrets-scanner.sh repo-scan`).
2. Run the helper script to create the scheduler job:

```bash
cd infra/cloud_scheduler
PROJECT=nexusshield-prod LOCATION=us-central1 ./create_vuln_scan_job.sh
```

Notes:
- The script posts to the Cloud Build triggers run endpoint; replace `VULN-SCAN-TRIGGER` with your trigger ID.
- Ensure the Cloud Scheduler service account has permission to invoke Cloud Build triggers.
