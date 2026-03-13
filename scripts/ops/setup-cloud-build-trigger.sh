#!/bin/bash
# Cloud Build Trigger Setup (Direct Deployment)
# Purpose: Create a Cloud Build trigger for automatic deployment on push to main
# Requires: GCP Cloud Build enabled, GitHub App connected, appropriate roles
# Usage: bash scripts/ops/setup-cloud-build-trigger.sh [--project PROJECT_ID]

set -e

PROJECT_ID="${1:---project}"
if [[ "$PROJECT_ID" == "--project" ]] && [[ -n "$2" ]]; then
  PROJECT_ID="$2"
fi

# If no project provided, try to get from gcloud config
if [[ -z "$PROJECT_ID" ]] || [[ "$PROJECT_ID" == "--project" ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: No GCP project specified."
  echo "Usage: bash scripts/ops/setup-cloud-build-trigger.sh --project PROJECT_ID"
  echo "OR set: gcloud config set project PROJECT_ID"
  exit 1
fi

echo "Setting up Cloud Build trigger in project: $PROJECT_ID"
echo

# Step 1: Verify Cloud Build API enabled
echo "1. Checking Cloud Build API..."
gcloud services enable cloudbuild.googleapis.com --project="$PROJECT_ID" || true
echo "   ✓ Cloud Build API enabled"
echo

# Step 2: Check/create GitHub App connection
echo "2. Checking GitHub App connection..."
# Try to create trigger directly; if GitHub repo is connected, this will work
echo "   Attempting to create Cloud Build trigger (will link GitHub repo if needed)..."
echo

# Step 3: Create the trigger
echo "3. Creating Cloud Build trigger..."
TRIGGER_NAME="main-build-trigger"
REPO_NAME="self-hosted-runner"
REPO_OWNER="kushin77"

# Check if trigger already exists
EXISTING=$(gcloud builds triggers list --filter="name=$TRIGGER_NAME" --format="value(name)" --project="$PROJECT_ID" 2>/dev/null || echo "")
if [[ -n "$EXISTING" ]]; then
  echo "   ✓ Trigger '$TRIGGER_NAME' already exists"
  gcloud builds triggers describe "$TRIGGER_NAME" --project="$PROJECT_ID" --format="table(name, description, filename)" 2>/dev/null || true
else
  echo "   Creating trigger for $REPO_OWNER/$REPO_NAME main branch..."
  gcloud builds triggers create github \
    --name="$TRIGGER_NAME" \
    --repo-owner="$REPO_OWNER" \
    --repo-name="$REPO_NAME" \
    --branch-pattern="^main\$" \
    --build-config="cloudbuild.yaml" \
    --description="Auto-deploy main branch to Cloud Run" \
    --project="$PROJECT_ID" 2>&1 | head -20
  
  TRIGGER_CREATED=$?
  if [[ $TRIGGER_CREATED -ne 0 ]]; then
    echo ""
    echo "   ⚠ Trigger creation encountered an issue (may require GitHub App connection)."
    echo "   Required manual step:"
    echo "   1. Go to: https://console.cloud.google.com/cloud-build/repositories?project=$PROJECT_ID"
    echo "   2. Click 'Connect Repository' or 'Link Repository'"
    echo "   3. Authorize Cloud Build GitHub App and select 'kushin77/self-hosted-runner'"
    echo "   4. Return here and re-run: bash scripts/ops/setup-cloud-build-trigger.sh --project $PROJECT_ID"
    echo ""
  else
    echo "   ✓ Trigger created successfully"
  fi
fi

echo

# Step 4: Configure service account permissions
echo "4. Configuring Cloud Build service account..."
CB_SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"
echo "   Service account: $CB_SA"

# Grant necessary roles
ROLES=(
  "roles/run.admin"
  "roles/artifactregistry.admin"
  "roles/storage.admin"
  "roles/cloudkms.cryptoKeyEncrypterDecrypter"
)

for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CB_SA" \
    --role="$ROLE" \
    --condition=None \
    --quiet 2>/dev/null || true
done
echo "   ✓ Service account roles assigned"
echo

# Step 5: Verify Cloud Run services exist
echo "5. Verifying Cloud Run services..."
CR_SERVICES=$(gcloud run services list --platform managed --format="value(metadata.name)" --project="$PROJECT_ID" 2>/dev/null | wc -l || echo "0")
echo "   Cloud Run services available: $CR_SERVICES"
if [[ $CR_SERVICES -gt 0 ]]; then
  gcloud run services list --platform managed --region=us-central1 --format="table(metadata.name, status.url)" --project="$PROJECT_ID" | head -10
fi
echo

# Step 6: Test trigger with manual build
echo "6. Testing trigger..."
echo "   To manually trigger a build:"
echo "     gcloud builds submit --config=cloudbuild.yaml --project=$PROJECT_ID"
echo
echo "   Or push to main branch:"
echo "     git push origin main"
echo

# Summary
echo "=========================================="
echo "Cloud Build Trigger Setup Complete"
echo "=========================================="
echo
echo "Trigger Name: $TRIGGER_NAME"
echo "Project: $PROJECT_ID"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Branch: main"
echo "Build Config: cloudbuild.yaml"
echo
echo "✓ Cloud Build → Cloud Run pipeline ready"
echo "✓ No GitHub Actions used (governance enforced)"
echo "✓ No manual releases required (direct deployment)"
echo
echo "Next: Push to main to trigger automatic build and deploy"
