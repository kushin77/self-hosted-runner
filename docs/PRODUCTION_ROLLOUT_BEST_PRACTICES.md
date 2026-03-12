# Production Rollout Best Practices

This runbook describes recommended best-practice steps for the Phase-5 production rollout, verification, and rollback. Use these commands from an account with the required permissions. Always capture audit logs and snapshots before making changes.

## 1) Pre-checks (must do)
- Confirm you have access to the production service accounts and cluster admin roles.
- Export useful env vars:

```bash
export PROJECT=nexusshield-prod
export SA=deployer-run@${PROJECT}.iam.gserviceaccount.com
export PROM_URL=http://<prom-host>:9090
export AM_URL=http://<alertmanager-host>:9093
export LB_NAME=<load-balancer-name>
```

## 2) GCP IAM (least privilege grants required)
If `deploy-gcp-monitoring.sh` failed with IAM errors, grant these roles to the monitoring/deployer service account:

```bash
# Grant logging configuration writer (for sink creation)
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/logging.configWriter"

# Grant monitoring dashboard editor
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/monitoring.dashboardEditor"

# Optional: bigquery job creator for SLA queries
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/bigquery.jobUser"
```

Re-run the GCP monitoring deployment after roles are set:

```bash
bash scripts/monitoring/deploy-gcp-monitoring.sh
```

## 3) Verification commands (post-deploy)
- GCP Logging sinks:

```bash
gcloud logging sinks list --project=${PROJECT}
gcloud monitoring dashboards list --project=${PROJECT}
gcloud monitoring alert-policies list --project=${PROJECT}
```

- AWS (CloudWatch):

```bash
aws cloudwatch describe-alarms --region us-east-1
aws cloudwatch get-dashboard --dashboard-name "credential-failover-dashboard" --region us-east-1
```

- Prometheus / Alertmanager (if present):

```bash
curl -fsS ${PROM_URL}/-/ready
curl -fsS ${PROM_URL}/api/v1/alerts | jq '.'
curl -fsS ${AM_URL}/api/v2/alerts | jq '.'
```

## 4) Baseline collection (24-hour)
Start continuous collectors to capture baseline metrics for 24 hours.

```bash
# Cost snapshot now
bash scripts/monitoring/track-regional-costs.sh > logs/cost-snapshot-$(date -u +%Y%m%dT%H%M%SZ).txt

# Start tracing instrumentation once to generate traces (already available)
bash scripts/observability/tracing-instrumentation.sh

# Ensure Cloud Scheduler jobs are enabled (these were created by cost script)
gcloud scheduler jobs list --project=${PROJECT} || true
```

## 5) 1% Canary / Smoke test (traffic split)
Prefer a weighted LB or traffic-gating feature flag. Example using a load balancer weight update (replace with your LB provider):

```bash
# Example: update backend weight (pseudo-command)
# set 1% traffic to new backend
gcloud compute backend-services update-backend ${LB_NAME} --balancing-mode=RATE --max-rate-per-instance=... \
  --project=${PROJECT}

# Validate for 30 minutes, monitor tracing + alerts, then increase to 10%, 25%, 50%, 100%
```

If you don't control LB weights, use application feature flags to route 1% of requests.

## 6) Rollback plan
- Immediately revert LB weights to previous state:

```bash
# revert to previous (100%)
gcloud compute backend-services update-backend ${LB_NAME} --backends=... --project=${PROJECT}
```

- If Vault or cache issues: re-enable previous credential layer by flipping internal feature flag to force AWS STS primary path.
- Always capture `logs/*.jsonl` for postmortem.

## 7) Alert thresholds & runbook
- Ensure these alerts exist and are tuned:
  - OIDC assume-role latency p95 > 2000ms
  - Failover rate > 1% (indicates upstream issues)
  - Vault error rate > 0.1%
  - Cache hit rate < 92%

For each alert, follow the runbook in `docs/PHASE5_COMPLETION_CERTIFICATE_20260312.md` and escalate to on-call.

## 8) Post-rollout actions
- Archive final audit logs to S3 with Object Lock.
- Generate final Phase-5 sign-off certificate and include all JSONL audit logs.

---

Documented by automation. Adjust commands to match your environment and credentials.
