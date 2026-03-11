#!/usr/bin/env bash
set -euo pipefail

# Orchestrated, idempotent deployment for prevent-releases enforcement service.
# Creates service account, GSM secrets, deploys Cloud Run (allow unauthenticated),
# creates Cloud Scheduler poll job, and monitoring alerts. Safe to re-run.

PROJECT=${PROJECT:-nexusshield-prod}
REGION=${REGION:-us-central1}
SERVICE=${SERVICE:-prevent-releases}
IMAGE=${IMAGE:-us-central1-docker.pkg.dev/${PROJECT}/production-portal-docker/${SERVICE}:latest}
SA_NAME=${SA_NAME:-nxs-prevent-releases-sa}
SA_EMAIL=${SA_EMAIL:-${SA_NAME}@${PROJECT}.iam.gserviceaccount.com}
ROLE_ID=${ROLE_ID:-deployerMinimal}
DEPLOYER_SA_NAME=${DEPLOYER_SA_NAME:-deployer-sa}
DEPLOYER_SA_EMAIL=${DEPLOYER_SA_EMAIL:-${DEPLOYER_SA_NAME}@${PROJECT}.iam.gserviceaccount.com}

echo "Orchestrated deploy: project=$PROJECT region=$REGION service=$SERVICE image=$IMAGE sa=$SA_EMAIL"

ensure_sa() {
  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Service account $SA_EMAIL exists"
    return 0
  fi

  echo "Creating service account $SA_EMAIL"
  if ! gcloud iam service-accounts create "$SA_NAME" --project="$PROJECT" --display-name="Prevent releases Cloud Run SA"; then
    echo "Failed to create service account. Ensure caller has 'iam.serviceAccounts.create' permission or create the SA manually:" >&2
    echo "  gcloud iam service-accounts create $SA_NAME --project=$PROJECT --display-name=\"Prevent releases Cloud Run SA\"" >&2
    return 1
  fi

  echo "Granting minimal roles to $SA_EMAIL"
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA_EMAIL" --role="roles/run.admin" || true
  gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" || true
}

ensure_deployer_role_and_sa() {
  # Create a minimal custom role and deployer service account on first run (idempotent).
  if gcloud iam roles describe "$ROLE_ID" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Custom role $ROLE_ID exists"
  else
    echo "Creating custom role $ROLE_ID (minimal deployer)"
    cat > /tmp/deployer-role.json <<'EOF'
{
  "title": "Deployer Minimal",
  "description": "Minimal permissions for prevent-releases deploy",
  "includedPermissions": [
    "iam.serviceAccounts.create",
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.list",
    "iam.serviceAccounts.actAs",
    "run.services.create",
    "run.services.update",
    "run.services.get",
    "run.services.list",
    "secretmanager.secrets.create",
    "secretmanager.versions.add",
    "secretmanager.secrets.get",
    "secretmanager.secrets.update",
    "cloudbuild.builds.create",
    "cloudscheduler.jobs.create",
    "monitoring.alertPolicies.create",
    "logging.configWriter"
  ]
}
EOF
    if ! gcloud iam roles create "$ROLE_ID" --project="$PROJECT" --file=/tmp/deployer-role.json >/dev/null 2>&1; then
      echo "Unable to create custom role $ROLE_ID (missing permissions)." >&2
      echo "Please create role manually or grant project owner the ability to create it. See docs/DEployer_ROLE_INSTRUCTIONS.md" >&2
    else
      echo "Created custom role $ROLE_ID"
    fi
  fi

  if gcloud iam service-accounts describe "$DEPLOYER_SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Deployer service account $DEPLOYER_SA_EMAIL exists"
  else
    echo "Creating deployer service account $DEPLOYER_SA_EMAIL"
    if ! gcloud iam service-accounts create "$DEPLOYER_SA_NAME" --project="$PROJECT" --display-name="Deployer SA" >/dev/null 2>&1; then
      echo "Unable to create deployer service account (missing iam.serviceAccounts.create)." >&2
      echo "You can create it manually and bind role projects/$PROJECT/roles/$ROLE_ID to it." >&2
    else
      echo "Created deployer service account $DEPLOYER_SA_EMAIL"
      # Bind custom role if it exists
      if gcloud iam roles describe "$ROLE_ID" --project="$PROJECT" >/dev/null 2>&1; then
        gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$DEPLOYER_SA_EMAIL" --role="projects/${PROJECT}/roles/${ROLE_ID}" || true
        echo "Bound custom role $ROLE_ID to $DEPLOYER_SA_EMAIL"
      fi
    fi
  fi
}

ensure_secret() {
  local name="$1"
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Secret $name exists"
  else
    printf 'placeholder' | gcloud secrets create "$name" --data-file=- --project="$PROJECT"
    echo "Created secret $name (placeholder)"
  fi
  gcloud secrets add-iam-policy-binding "$name" --project="$PROJECT" --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" || true
}

deploy_run() {
  echo "Deploying Cloud Run service $SERVICE (allow unauthenticated)"
  gcloud run deploy "$SERVICE" \
    --project="$PROJECT" --region="$REGION" --image="$IMAGE" --platform=managed \
    --service-account="$SA_EMAIL" \
    --allow-unauthenticated \
    --set-secrets="GITHUB_WEBHOOK_SECRET=github-app-webhook-secret:latest" \
    --set-secrets="GITHUB_TOKEN=github-app-token:latest" \
    --quiet
}

create_scheduler() {
  local job=prevent-releases-poll
  if gcloud scheduler jobs describe "$job" --project="$PROJECT" --location="$REGION" >/dev/null 2>&1; then
    echo "Scheduler job $job exists"
    return 0
  fi

  local url
  url=$(gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)') || true
  if [ -z "$url" ]; then
    echo "Cloud Run URL not found; ensure service deployed before creating scheduler" >&2
    return 1
  fi

  echo "Creating Cloud Scheduler job $job -> $url/api/poll"
  gcloud scheduler jobs create http "$job" --project="$PROJECT" --location="$REGION" \
    --schedule="*/1 * * * *" --http-method=POST --uri="$url/api/poll" \
    --oidc-service-account-email="$SA_EMAIL" --time-zone="Etc/UTC" || true
}

create_alerts() {
  echo "Creating logs-based metric and alerting policies (idempotent)"
  METRIC_NAME=secret_access_denied_metric
  LOG_FILTER='resource.type="cloud_run_revision" AND (textPayload:"Permission denied" OR textPayload:"secretmanager.secretAccessor" OR textPayload:"Permission denied on secret")'
  if gcloud logging metrics describe "$METRIC_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Metric $METRIC_NAME exists"
  else
    gcloud logging metrics create "$METRIC_NAME" --description="Detect secret access denied in Cloud Run logs" --log-filter="$LOG_FILTER" --project="$PROJECT" || true
  fi

  # Error-rate alert: best-effort creation, may require monitoring permissions
  gcloud alpha monitoring policies create --project="$PROJECT" \
    --condition-display-name="Prevent-releases error rate" \
    --condition-filter="resource.type=\"cloud_run_revision\" AND resource.label.\"service_name\"=\"$SERVICE\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.label.\"response_code\">=\"500\"" \
    --condition-compare-duration=300s --condition-threshold-value=1 --display-name="prevent-releases 5xx error rate" || true
}

main() {
  echo "Starting orchestrated deploy (idempotent)."
  if ! gcloud config get-value project >/dev/null 2>&1; then
    echo "gcloud not configured or not authenticated. Please run 'gcloud auth login' and 'gcloud config set project $PROJECT'" >&2
    exit 1
  fi

  # Attempt to create minimal deployer role and deployer SA on first-run (best-effort).
  ensure_deployer_role_and_sa || true

  ensure_sa || echo "Warning: failed to create service account; proceeding if it already exists"

  for s in github-app-private-key github-app-id github-app-webhook-secret github-app-token; do
    ensure_secret "$s"
  done

  deploy_run || { echo "Cloud Run deploy failed; check permissions and run infra/deploy-prevent-releases.sh manually" >&2; exit 1; }

  create_scheduler || echo "Scheduler creation skipped or failed"
  create_alerts || echo "Alert creation skipped or failed"

  echo "Orchestrated deploy complete. Verify Cloud Run URL and monitoring alerts." 

  if command -v gh >/dev/null 2>&1 && [ -n "${GITHUB_TOKEN-}" ]; then
    echo "Posting audit comment to issue #2524"
    gh issue comment 2524 --body-file scripts/github/comment-2524.txt --repo kushin77/self-hosted-runner || true
  fi
}

main "$@"
