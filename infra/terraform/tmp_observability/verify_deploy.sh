#!/bin/bash
# Verify synthetic health-check deployment resources and metric
set -euo pipefail

PROJECT="${1:-nexusshield-prod}"
REGION="${2:-us-central1}"
METRIC="custom.googleapis.com/synthetic/uptime_check"
FUNCTION_NAME="synthetic-health-check"
TOPIC_NAME="synthetic-health-check-topic"
SCHEDULER_NAME="synthetic-health-check-scheduler"

echo "Verifying deployment in project=$PROJECT region=$REGION"

echo "\n1) Cloud Function"
if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT" --format='yaml(name,entryPoint,status,buildConfig.runtime,serviceConfig.uri)'
else
  echo "✗ Cloud Function '$FUNCTION_NAME' not found"
fi

echo "\n2) Pub/Sub Topic"
if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT" --format='value(name)'
else
  echo "✗ Pub/Sub topic '$TOPIC_NAME' not found"
fi

echo "\n3) Cloud Scheduler Job"
if gcloud scheduler jobs describe "$SCHEDULER_NAME" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud scheduler jobs describe "$SCHEDULER_NAME" --location="$REGION" --project="$PROJECT" --format='yaml(name,schedule,targetPubsubTopic,state)'
else
  echo "✗ Scheduler job '$SCHEDULER_NAME' not found"
fi

echo "\n4) Metric Samples (last 6 hours)"
if gcloud monitoring time-series list --project="$PROJECT" --filter="metric.type=\"$METRIC\"" --limit=1 >/dev/null 2>&1; then
  gcloud monitoring time-series list --project="$PROJECT" --filter="metric.type=\"$METRIC\"" --limit=5 --format='yaml(points)'
else
  echo "✗ Metric '$METRIC' not found or no data yet"
fi

echo "\nVerification complete. If resources missing, redeploy with credential-enabled detector."
