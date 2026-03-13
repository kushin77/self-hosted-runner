#!/usr/bin/env bash
# Create a Cloud Scheduler job that triggers a weekly vulnerability scan via Cloud Build
set -euo pipefail

PROJECT=${PROJECT:-nexusshield-prod}
LOCATION=${LOCATION:-us-central1}
SCHEDULE=${SCHEDULE:-"0 3 * * 1"} # At 03:00 UTC every Monday
JOB_NAME=${JOB_NAME:-vuln-scan-weekly}

echo "Creating Cloud Scheduler job '${JOB_NAME}' in project ${PROJECT} (${LOCATION})"

gcloud scheduler jobs create http "$JOB_NAME" \
  --project="$PROJECT" \
  --location="$LOCATION" \
  --schedule="$SCHEDULE" \
  --uri="https://cloudbuild.googleapis.com/v1/projects/${PROJECT}/triggers:run" \
  --http-method=POST \
  --headers="Content-Type: application/json" \
  --message-body='{"projectId":"'$PROJECT'","triggerId":"VULN-SCAN-TRIGGER"}' || true

echo "Note: Create a Cloud Build trigger named 'VULN-SCAN-TRIGGER' that runs the repository vulnerability scan (e.g., runs 'bash security/enhanced-secrets-scanner.sh repo-scan' or an equivalent build step)."
echo "Adjust PROJECT, LOCATION, SCHEDULE and trigger ID as needed."

echo "Done."
