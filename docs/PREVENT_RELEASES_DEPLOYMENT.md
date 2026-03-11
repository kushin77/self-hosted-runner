# Prevent-Releases Service Deployment Guide

**Status**: PR Ready, Deployment Guide Complete  
**PR**: https://github.com/kushin77/self-hosted-runner/pull/2618  
**Issue**: #2524 (Closed - action triage complete)

## Overview

This guide describes the complete, idempotent, hands-off deployment of the `prevent-releases` GitHub App enforcement service to Cloud Run. The service enforce repository governance policies (no releases, no tags) and runs via Cloud Scheduler polling.

## Architecture

```
GitHub Webhook → Cloud Run (prevent-releases, unauthenticated)
                 ├─ Validates HMAC-SHA256 signature
                 ├─ Reads secrets from GSM (GITHUB_TOKEN, GITHUB_WEBHOOK_SECRET)
                 └─ Creates audit issues on enforcement 

Cloud Scheduler → Cloud Run (/api/poll) → Cleanup enforcement
                  Schedule: */1 * * * * (every minute)
                  Auth: OIDC service account
```

## Prerequisites

- GCP Project: `nexusshield-prod`
- gcloud CLI authenticated with deployer permissions:
  - `roles/iam.serviceAccountAdmin` or `roles/iam.securityAdmin`
  - `roles/run.admin`
  - `roles/secretmanager.admin`
  - `roles/logging.configWriter`
  - `roles/monitoring.admin`
  - `roles/cloudscheduler.admin`
- Docker image already built: `us-central1-docker.pkg.dev/nexusshield-prod/production-portal-docker/prevent-releases:latest`

## Deployment Options

### Option A: Orchestrator Script (Recommended)

Idempotent, comprehensive deployment with all components:

```bash
# From repo root, ensure gcloud is authenticated
gcloud auth login
gcloud config set project nexusshield-prod

# Run orchestrator (safe to re-run)
bash infra/complete-deploy-prevent-releases.sh
```

This will (idempotently):
1. Create service account `nxs-prevent-releases-sa@nexusshield-prod.iam.gserviceaccount.com`
2. Create/grant GSM secrets: `github-app-webhook-secret`, `github-app-private-key`, `github-app-id`, `github-app-token`
3. Deploy Cloud Run service with `--allow-unauthenticated` and secret injection
4. Create Cloud Scheduler job `prevent-releases-poll` (*/1 * * * *)
5. Create monitoring alerts and logs-based metrics

### Option B: Cloud Build Submission

Uses Cloud Build infrastructure for deployment:

```bash
cd /home/akushnir/self-hosted-runner
gcloud builds submit --config=infra/cloudbuild-prevent-releases.yaml --no-source --project=nexusshield-prod
```

This builds the prevent-releases image and executes the same deployment steps as Option A.

### Option C: Individual Manual Steps

For fine-grained control, run individually:

```bash
# 1. Ensure service account exists
SA_EMAIL=nxs-prevent-releases-sa@nexusshield-prod.iam.gserviceaccount.com
gcloud iam service-accounts create nxs-prevent-releases-sa --project=nexusshield-prod \
  --display-name="Prevent releases Cloud Run SA"

# 2. Create secrets (or update placeholders)
for s in github-app-webhook-secret github-app-private-key github-app-id github-app-token; do
  printf 'placeholder' | gcloud secrets create "$s" --data-file=- --project=nexusshield-prod 2>/dev/null || true
done

# 3. Grant SA secret access
for s in github-app-webhook-secret github-app-private-key github-app-id github-app-token; do
  gcloud secrets add-iam-policy-binding "$s" --project=nexusshield-prod \
    --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" || true
done

# 4. Deploy Cloud Run with unauthenticated + secret injection
gcloud run deploy prevent-releases \
  --project=nexusshield-prod --region=us-central1 \
  --image=us-central1-docker.pkg.dev/nexusshield-prod/production-portal-docker/prevent-releases:latest \
  --service-account=$SA_EMAIL \
  --allow-unauthenticated \
  --set-secrets="GITHUB_WEBHOOK_SECRET=github-app-webhook-secret:latest" \
  --set-secrets="GITHUB_TOKEN=github-app-token:latest" \
  --quiet

# 5. Create Cloud Scheduler job
RUN_URL=$(gcloud run services describe prevent-releases --project=nexusshield-prod --region=us-central1 --format='value(status.url)')
gcloud scheduler jobs create http prevent-releases-poll --project=nexusshield-prod --location=us-central1 \
  --schedule="*/1 * * * *" --http-method=POST --uri="$RUN_URL/api/poll" \
  --oidc-service-account-email=$SA_EMAIL --time-zone="Etc/UTC"

# 6. Create monitoring alerts
bash scripts/monitoring/create-alerts.sh RUN_NOW=1
```

## Post-Deployment Verification

```bash
# 1. Verify Cloud Run deployment
gcloud run services describe prevent-releases --project=nexusshield-prod --region=us-central1

# 2. Check health endpoint
curl -s https://prevent-releases-2tqp6t4txq-uc.a.run.app/health

# 3. Verify Cloud Scheduler job
gcloud scheduler jobs describe prevent-releases-poll --project=nexusshield-prod --location=us-central1

# 4. Check secret access
gcloud secrets get-iam-policy github-app-webhook-secret --project=nexusshield-prod

# 5. Review monitoring alerts
gcloud alpha monitoring policies list --project=nexusshield-prod --filter="displayName:'prevent-releases'"
```

## Configuration

### Required Secrets (in Google Secret Manager)

Store actual values in these secrets (defaults to 'placeholder'):

- `github-app-webhook-secret` — HMAC signing secret for webhook validation (random string, ~32 chars)
- `github-app-token` — GitHub App personal access token or OAuth token (with repo:admin scope)
- `github-app-private-key` — GitHub App private key (PEM format)
- `github-app-id` — GitHub App ID (numeric, from GitHub settings)

Populate after deployment:

```bash
PROJECT=nexusshield-prod

# Example: update webhook secret
echo -n "your-webhook-secret-here" | gcloud secrets versions add github-app-webhook-secret \
  --data-file=- --project=$PROJECT

# Example: update GitHub token
echo -n "ghp_xxxxxxxxxxxx" | gcloud secrets versions add github-app-token \
  --data-file=- --project=$PROJECT
```

### Cloud Run Configuration

- **Service**: `prevent-releases`
- **Region**: `us-central1`
- **Allow unauthenticated**: `true`
- **Service Account**: `nxs-prevent-releases-sa@nexusshield-prod.iam.gserviceaccount.com`
- **Secrets Injected**:
  - `GITHUB_WEBHOOK_SECRET` (from GSM secret)
  - `GITHUB_TOKEN` (from GSM secret)

### Cloud Scheduler Configuration

- **Job**: `prevent-releases-poll`
- **Schedule**: `*/1 * * * *` (every minute)
- **HTTP Method**: `POST`
- **Endpoint**: `<CLOUD_RUN_URL>/api/poll`
- **Auth**: OIDC service account token
- **Timezone**: `Etc/UTC`

### Monitoring & Alerting

Alerts created (all idempotent):

1. **Secret Access Denied** — Alert when service account cannot access GSM secrets
   - Metric: `logging.googleapis.com/user/secret_access_denied_metric`
   - Threshold: > 1 occurrence in 5 minutes

2. **Prevent-Releases 5xx Error Rate** — Alert on high error rate
   - Resource: `cloud_run_revision` (service_name = prevent-releases)
   - Metric: `run.googleapis.com/request_count` (response_code >= 500)
   - Threshold: > 1 in 5 minutes

View alerts:

```bash
gcloud alpha monitoring policies list --project=nexusshield-prod \
  --filter="displayName:'prevent-releases' OR displayName:'Secret Access'"
```

## Troubleshooting

### Cloud Run Service Not Found

```bash
# Service not deployed yet — run deployment
bash infra/complete-deploy-prevent-releases.sh
```

### 401 Unauthorized on Webhook

Cloud Run service is allowing unauthenticated invocations, but validating HMAC. Check:

1. Webhook secret matches `github-app-webhook-secret` in GSM
2. GitHub App webhook is configured with correct URL and secret
3. Review Cloud Run logs: `gcloud logs read resource.type=cloud_run_revision resource.labels.service_name=prevent-releases --project=nexusshield-prod --limit=50`

### Secrets Not Accessible

Verify service account has `secretmanager.secretAccessor` role:

```bash
gcloud secrets get-iam-policy github-app-webhook-secret --project=nexusshield-prod \
  --format='table(bindings.members)' | grep nxs-prevent-releases-sa
```

### Scheduler Job Not Running

```bash
# Check job status
gcloud scheduler jobs describe prevent-releases-poll --project=nexusshield-prod --location=us-central1

# Check last run
gcloud scheduler jobs run prevent-releases-poll --project=nexusshield-prod --location=us-central1
```

## Rollback

To disable enforcement (emergency):

```bash
# Pause scheduler job
gcloud scheduler jobs pause prevent-releases-poll --project=nexusshield-prod --location=us-central1

# Restrict Cloud Run to owner only (remove allUsers)
gcloud run services remove-iam-policy-binding prevent-releases \
  --member=allUsers --role=roles/run.invoker \
  --project=nexusshield-prod --region=us-central1

# Or delete the service
gcloud run services delete prevent-releases --project=nexusshield-prod --region=us-central1 --quiet
```

## Related Documentation

- [Incident Runbook](docs/INCIDENT_RUNBOOK.md)
- [GitHub App Configuration](docs/GITHUB_APP_PREVENT_RELEASES.md)
- [Monitoring Setup](docs/MONITORING_SETUP_GUIDE.md)
- [Alerting Guide](docs/ALERTING_AND_MONITORING.md)
