Incidents webhook (Google Secret Manager)
======================================

This file documents the expected GSM secret used by the notifier: `incidents-webhook` in project `nexusshield-prod`.

Purpose
- The `notify_on_failure.sh` script reads the `incidents-webhook` secret when `INCIDENT_WEBHOOK` is not set. The secret should contain a single-line webhook URL (e.g., Slack/Teams/other HTTP endpoint).

Create or update the secret (example):

```bash
# Create secret (if not exists)
gcloud secrets create incidents-webhook --project=nexusshield-prod --replication-policy="automatic"

# Store webhook value (replace with real URL)
echo -n "https://example.com/your-webhook-path" | gcloud secrets versions add incidents-webhook --data-file=- --project=nexusshield-prod
```

Security
- Only grant access to this secret to operator/service accounts that need to post alerts. Use IAM to restrict `secretmanager.versions.access`.

Notes
- The repo currently contains a placeholder value; replace it with your real webhook before enabling notifications in production.
