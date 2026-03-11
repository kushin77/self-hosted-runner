Title: Unblock org policy and compliance group for uptime checks (runbook attached)

Body:

We implemented a synthetic health-check Cloud Function and scheduler as a temporary, automated workaround for uptime-check blockers.

Background:
- Terraform-native uptime check creation failed due to monitored-resource validation and org policy preventing unauthenticated Cloud Run invocations.
- To avoid blocking production observability, we've added a function that mints ID tokens and posts to the protected service, and writes a custom metric `custom.googleapis.com/synthetic/uptime_check`.

Required admin actions to fully restore Terraform-managed uptime checks and compliance integration:

1. Create the `cloud-audit` IAM group and assign the required monitoring/ops roles (see ISSUE #2469).
2. Provide a controlled exception or a service-account-based probe pattern so uptime checks can authenticate to Cloud Run without granting global unauthenticated access (see ISSUE #2468). Options:
   - Allow specific probe service account(s) and grant them `run.invoker` on the target.
   - Add an exception to the org policy for the monitoring probe's SA.
   - Use API Gateway + auth with a probe SA.

We've committed the synthetic checker and a Monitoring alerting terraform snippet at `infra/terraform/tmp_observability/monitoring_synthetic.tf`.

Action requested from admins:
- Please create the `cloud-audit` group and confirm membership and roles.
- Decide which method to authenticate probes and communicate the selected approach so we can remove the synthetic workaround and enable Terraform-managed uptime checks.

Runbook reference: `ops/UNBLOCK_BLOCKERS_RUNBOOK.md`
