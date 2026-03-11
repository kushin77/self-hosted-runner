#!/usr/bin/env bash
set -euo pipefail

# create-alerts.sh
# Creates logs-based metrics and prints recommended gcloud commands to create
# alerting policies. Run as a project owner or monitoring admin.

PROJECT=${PROJECT:-nexusshield-prod}
SERVICE_NAME=${SERVICE_NAME:-prevent-releases}

echo "Creating logs-based metric for secret access failures..."
METRIC_NAME=secret_access_denied_metric
LOG_FILTER='resource.type="cloud_run_revision" AND (textPayload:"Permission denied" OR textPayload:"secretmanager.secretAccessor" OR textPayload:"Permission denied on secret")'

if gcloud logging metrics describe "$METRIC_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Metric $METRIC_NAME already exists; skipping creation"
else
  gcloud logging metrics create "$METRIC_NAME" --description="Detect secret access denied in Cloud Run logs" --log-filter="$LOG_FILTER" --project="$PROJECT"
  echo "Created logs-based metric: $METRIC_NAME"
fi

cat <<'EOF'

Recommended next steps (run as Monitoring Admin):

1) Create an alerting policy on the logs-based metric (secret access failures):

gcloud alpha monitoring policies create --project=PROJECT \
  --condition-display-name="Secret Access Denied" \
  --condition-filter='metric.type="logging.googleapis.com/user/secret_access_denied_metric"' \
  --condition-compare-duration=300s \
  --condition-threshold-value=1 \
  --display-name="Secret Access Denied Alert"

2) Create an error-rate alert for Cloud Run service:

# Alert when 5xx error rate > 1% over 5 minutes for the service
# Adjust the filter to match your project and service name

gcloud alpha monitoring policies create --project=PROJECT \
  --condition-display-name="Prevent-releases error rate" \
  --condition-filter='resource.type="cloud_run_revision" AND resource.label."service_name"="SERVICE_NAME" AND metric.type="run.googleapis.com/request_count" AND metric.label."response_code">="500"' \
  --condition-compare-duration=300s \
  --condition-threshold-value=1 \
  --display-name="prevent-releases 5xx error rate"

3) Create a policy to alert when Cloud Scheduler job state != ENABLED by monitoring scheduler job metrics or via logs.

If you want, I can attempt to create the alerting policies automatically; confirm and I will run the recommended commands with project "$PROJECT" and service "$SERVICE_NAME".
EOF
