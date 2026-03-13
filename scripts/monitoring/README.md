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
