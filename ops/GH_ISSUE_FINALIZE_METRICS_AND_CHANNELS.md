Title: Finalize synthetic uptime metric and wire notification channels

Body:
We have deployed a synthetic health checker Cloud Function (synthetic-health-check) that probes the protected Cloud Run endpoint and attempts to write a custom TimeSeries metric `custom.googleapis.com/synthetic/uptime_check`.

Current state:
- Function deployed and active in project `nexusshield-prod` (revision synthetic-health-check-00010-waz).
- Pub/Sub topic `synthetic-health-topic` and Cloud Scheduler job `synthetic-health-schedule` exist and trigger the function.
- Metric write attempts currently fail due to TimeInterval validation from the Monitoring API; as a fallback the function now emits structured logs with key `fallback_metric` for conversion into a logging-based metric.

Requested admin actions (immutable/idempotent steps):
1. Create a logging-based metric in Cloud Monitoring that extracts `fallback_metric` entries from Cloud Function logs. Use a stable metric name like `logging.googleapis.com/user/synthetic/uptime_check`.
2. Populate GSM with the notification-channel credentials and webhook(s) for alerting. Add the following secret names (example):
   - `projects/nexusshield-prod/secrets/ops-notify-slack` (JSON webhook payload)
   - `projects/nexusshield-prod/secrets/ops-notify-email` (email channel config)
3. Confirm Secret Manager secret paths in this issue comment so we can update Terraform alert policy with notification channel IDs.

Verification steps for admins (can be run non-interactively):
- Publish a test message to Pub/Sub: `gcloud pubsub topics publish synthetic-health-topic --project=nexusshield-prod --message='{"test":"verify"}'`
- Verify logs show structured `fallback_metric` entries in Cloud Functions logs.
- Create the logging-based metric and confirm datapoints appear within 1-2 minutes.
- Provide notification channel IDs (or populate GSM secrets) and we will attach them to the alert policy and finish verification.

Notes:
- All changes are designed to be idempotent and no-ops when re-run. We will not use GitHub Actions or PRs — we will commit directly to main as requested.
- Once GSM secrets and notification channel IDs are provided, we will update Terraform to attach channels to the alert policy, apply, and verify alerting end-to-end.

Refs: infra/functions/synthetic_health_check/main.py, infra/terraform/tmp_observability/monitoring_synthetic.tf
