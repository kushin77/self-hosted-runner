Cloud Cost Tracker — README
===========================

Overview
--------
This component collects multi-cloud cost data (GCP & AWS), detects anomalies, exports metrics for Prometheus, and generates a markdown report. Secrets are stored in Google Secret Manager (GSM) and the container reads GSM at runtime.

Quickstart (GSM-first)
----------------------
1. Create required secrets in GSM (example):

```bash
PROJECT=nexusshield-prod
# Slack webhook (raw URL)
gcloud secrets create slack-webhook --replication-policy="automatic" --project=$PROJECT || true
echo -n "https://hooks.slack.com/services/XXX/YYY/ZZZ" | gcloud secrets versions add slack-webhook --data-file=- --project=$PROJECT

# AWS credentials (JSON)
gcloud secrets create aws-credentials --replication-policy="automatic" --project=$PROJECT || true
cat > /tmp/aws-creds.json <<'EOF'
{"AWS_ACCESS_KEY_ID":"AKIA...","AWS_SECRET_ACCESS_KEY":"..."}
EOF
gcloud secrets versions add aws-credentials --data-file=/tmp/aws-creds.json --project=$PROJECT
```

2. Deploy to Kubernetes (recommended with Workload Identity or service account that can access GSM):

```bash
# Option A: Let the container fetch secrets from GSM directly (preferred)
kubectl apply -f k8s/cost-tracking-cronjob.yaml

# Option B: Sync GSM secrets into k8s and reference them (if GSM CSI driver not used)
./scripts/monitoring/sync_gsm_to_k8s.sh --project $PROJECT slack-webhook:slack-webhook aws-credentials:aws-credentials
# Then apply CronJob (adjust if you prefer referencing k8s secrets)
kubectl apply -f k8s/cost-tracking-cronjob.yaml
```

3. Build & push image (Cloud Build is integrated):

```bash
# Use Cloud Build (repo has a pipeline change that builds cost-tracker image)
gcloud builds submit --config cloudbuild.yaml --substitutions=_SHORT_SHA=$(git rev-parse --short HEAD)
```

Notes & Best Practices
----------------------
- Prefer Workload Identity or a K8s service account with limited permissions to access GSM rather than embedding secrets.
- Use `GSM_SLACK_SECRET` and `GSM_AWS_CREDENTIALS_SECRET` env vars (set to GSM secret names) so the container loads secrets at runtime.
- If you prefer, run `sync_gsm_to_k8s.sh` to create Kubernetes secrets from GSM values.
- Monitor Prometheus metrics at port 8000 and import the Grafana dashboard: `scripts/monitoring/dashboards/cost_monitoring_dashboard.json`.

Security
--------
- Do not store plaintext secrets in git. Use GSM only.
- Enable least-privilege IAM roles for the service account that accesses GSM (only `secretmanager.versions.access`).

Support
-------
If you want, I can:
- Trigger Cloud Build to build the `cost-tracker` image.
- Create the GSM secrets for you given secret values.
- Attempt to deploy the CronJob (requires cluster kubeconfig and IAM access).

Alert to GitHub Issue Triage
----------------------------

Use `scripts/monitoring/triage_alerts_to_github_issues.sh` to automatically:
- Create GitHub issues for new firing alerts
- Reuse existing issues for known active alerts (idempotent)
- Close issues automatically when alerts are resolved

Required environment variables:

```bash
export GITHUB_REPOSITORY="kushin77/self-hosted-runner"
export GITHUB_TOKEN="<token>"
export PROM_URL="http://prometheus:9090"
export AM_URL="http://alertmanager:9093"  # optional
```

GSM-first credential option:

```bash
export GCP_PROJECT_ID="nexusshield-prod"
export GITHUB_TOKEN_GSM_SECRET="github-token"
```

Run triage directly:

```bash
./scripts/monitoring/triage_alerts_to_github_issues.sh
```

Or enable from smoke test:

```bash
AUTO_TRIAGE_GITHUB_ISSUES=true \
PROM_URL="$PROM_URL" AM_URL="$AM_URL" \
./scripts/monitoring/smoke_test_alerts.sh
```

Scheduled Hands-Off Triage (systemd)
------------------------------------

To run triage every 5 minutes without GitHub Actions:

1. Install units:

```bash
sudo ./scripts/utilities/install-monitor-services.sh
```

2. Configure environment file:

```bash
sudo cp systemd/monitoring-alert-triage.env.example /etc/default/monitoring-alert-triage
sudo chmod 600 /etc/default/monitoring-alert-triage
```

3. Start timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now monitoring-alert-triage.timer
```

4. Verify:

```bash
systemctl status monitoring-alert-triage.timer
journalctl -u monitoring-alert-triage.service -n 100 --no-pager
```

Operational behavior and controls:
- Fail-safe no-op: if token retrieval fails or endpoints are unavailable, the service exits 0 and retries on next timer tick.
- Overlap-safe: concurrent runs are prevented with a lock file (`logs/monitoring-alert-issue-triage.lock`).
- Skip escalation: repeated skips create `logs/monitoring-alert-issue-triage.warning` for local operational signal.
- Status artifact: each run writes `logs/monitoring-alert-issue-triage.status` with `ok|skip|failed` and the latest reason.
- Audit retention: `TRIAGE_AUDIT_MAX_LINES` caps `logs/monitoring-alert-issue-triage.jsonl` growth.
- Strict mode: set `TRIAGE_STRICT_MODE=true` to fail the service on triage script errors instead of fail-safe skip.
