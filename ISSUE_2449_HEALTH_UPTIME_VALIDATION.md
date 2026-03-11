Title: Uptime check creation failed during tmp_observability apply

Summary:
- While enabling uptime checks via `infra/terraform/tmp_observability`, Terraform created the Secret Manager secret `uptime-check-token` and stored a generated token successfully.
- Creation of `google_monitoring_uptime_check_config` resources for backend and frontend failed with API error:
  - `Error creating UptimeCheckConfig: googleapi: Error 400: Error confirming monitored resource: type: "uptime-url" labels { key: "host" value: "...run.app" } is in project: 151423364222`

Diagnosis:
- The Monitoring API rejected monitored resource confirmation for the Cloud Run host during creation of uptime checks.
- This seems to be an API-side validation step that verifies the target host mapping; the host resolves to a Cloud Run domain and the API responded with a project confirmation error.
- Attempts to use `http_check.host` previously failed (provider schema mismatch). The module was updated to use `monitored_resource { type = "uptime-url" }` which matches other working configs, but the API still failed.

Remediation options (recommended priority):
1. Use a static secret token for health endpoint and redeploy Cloud Run services with the same token (via GSM -> env var). Then create uptime checks referencing that host and include the header. This avoids depending on the Monitoring API confirming a Cloud Run resource mapping.
2. Open a support ticket with GCP if the Monitoring API is incorrectly rejecting a valid Cloud Run domain for the tenancy/project.
3. As fallback, deploy a small external HTTP probe (Cloud Function or GCE instance with a public IP) in the same project to proxy the health check; have uptime checks target the proxy URL.

Next steps performed:

Recent test results:
- Created three uptime checks via `gcloud monitoring uptime create` (backend-health, backend-status, frontend).
- Performed curl validation against both services using the GSM token; both endpoints returned HTTP 401 Unauthorized for the tested paths (`/health` and `/`).


- Or, as a fallback, deploy a small external HTTP probe (Cloud Function or GCE instance with a public IP) in the same project to proxy the health check; have uptime checks target the proxy URL.
- Or, approve raising a GCP support request to investigate the Monitoring API validation.

Reference:
- tmp_observability root: infra/terraform/tmp_observability/main.tf
- health module: infra/terraform/modules/health/main.tf

Recorded-by: automation
Date: 2026-03-11
