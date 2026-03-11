# Unblock Blockers Runbook

This runbook implements an immediate workaround for uptime-check blockers (org policy preventing unauthenticated Cloud Run probes) by deploying a synthetic health-check Cloud Function which:

- Uses Application Default Credentials to mint an ID token for the target Cloud Run URL.
- Calls the target URL with an `Authorization: Bearer <id_token>` header.
- Writes a TimeSeries custom metric `custom.googleapis.com/synthetic/uptime_check` with value 1 (healthy) or 0 (unhealthy).
- Is triggered on a schedule via Cloud Scheduler → Pub/Sub.

Files added:

- `infra/functions/synthetic_health_check/main.py` — Cloud Function source.
- `infra/functions/synthetic_health_check/requirements.txt` — deps.
- `infra/terraform/tmp_observability/deploy_synthetic_health.sh` — deploy helper script.

Quick deploy (example):

```bash
cd infra/terraform/tmp_observability
./deploy_synthetic_health.sh my-project-id https://my-backend-xxxxx.a.run.app
```

Next steps and notes:

- Alerts: create a Monitoring alert policy that watches the custom metric `custom.googleapis.com/synthetic/uptime_check` and fires when the value is 0 for 1+ datapoints.
- IAM: Ensure the function's service account has permission to invoke the target Cloud Run service (roles/run.invoker) or the target accepts identity tokens for the function's service account.
- Hard blocker items that still require org admin action (we created issues):
  - ISSUE #2468 — org policy preventing unauthenticated Cloud Run access. Options: enable service-account-based probes, allow specific unauthenticated probes, or provide a managed probe SA. This runbook avoids needing that change.
  - ISSUE #2469 — compliance `cloud-audit` group creation. We prepared terraform snippets; a human admin must create the group and grant roles.

If you want, I can:
- Create the Monitoring alert policy terraform snippet and add it to the repo.
- Deploy the function and scheduler in your project (requires gcloud auth on this machine with sufficient IAM).
- Open/update the GitHub issues with the runbook and remediation steps.
