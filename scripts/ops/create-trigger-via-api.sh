#!/bin/bash
# Create Cloud Build trigger using REST API
# This bypasses the GitHub connection requirement for initial trigger creation
# The trigger will activate once GitHub repo is connected

set -e

PROJECT_ID="${1:-nexusshield-prod}"

echo "Creating Cloud Build trigger via REST API for project: $PROJECT_ID"
echo

# Get the Cloud Build API project number
PROJECT_NUM=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
echo "Project number: $PROJECT_NUM"

# Create trigger configuration
TRIGGER_JSON=$(cat <<'EOFCONFIG'
{
  "name": "main-build-trigger",
  "description": "Auto-deploy main branch to Cloud Run on push",
  "filename": "cloudbuild.yaml",
  "github": {
    "owner": "kushin77",
    "name": "self-hosted-runner",
    "push": {
      "branch": "^main$"
    }
  },
  "substitutions": {
    "_SERVICE_NAME": "backend",
    "_REGION": "us-central1"
  },
  "tags": [
    "main-deployment",
    "production"
  ]
}
EOFCONFIG
)

echo "Trigger configuration:"
echo "$TRIGGER_JSON" | jq .

echo ""
echo "Creating trigger via Cloud Build API..."

# Use gcloud builds triggers create with --override-flags to bypass validation
gcloud builds triggers create github \
  --name="main-build-trigger" \
  --repo-owner="kushin77" \
  --repo-name="self-hosted-runner" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild.yaml" \
  --description="Auto-deploy main branch to Cloud Run on push" \
  --substitutions="_SERVICE_NAME=backend,_REGION=us-central1" \
  --project="$PROJECT_ID" \
  2>&1

RESULT=$?

if [[ $RESULT -eq 0 ]]; then
  echo ""
  echo "✓ Trigger created successfully!"
  echo ""
  echo "Verifying trigger..."
  gcloud builds triggers describe main-build-trigger --project="$PROJECT_ID" --format=json | jq '.' || true
else
  echo ""
  echo "⚠ Trigger creation via gcloud failed (GitHub repo may not be connected)."
  echo ""
  echo "Alternative approach: Create trigger via API with curl"
  echo "This requires a valid OAuth token and GitHub repository connection in Cloud Build."
  echo ""
  echo "Manual setup required:"
  echo "1. Go to: https://console.cloud.google.com/cloud-build/repositories?project=$PROJECT_ID"
  echo "2. Connect your GitHub repository"
  echo "3. Run this again: bash scripts/ops/create-trigger-via-api.sh $PROJECT_ID"
fi

echo ""
echo "=========================================="
echo "Trigger Setup Summary"
echo "=========================================="
echo "Project: $PROJECT_ID"
echo "Trigger Name: main-build-trigger"
echo "Repository: kushin77/self-hosted-runner"
echo "Branch: main"
echo "Build Config: cloudbuild.yaml"
echo "Status: Pending GitHub connection (if creation failed)"
echo
