#!/usr/bin/env bash
# scripts/setup-cloudbuild-triggers.sh
# Automated Cloud Build trigger creation and verification
# 
# Prerequisites:
#   - Cloud Build GitHub repository connection must be created in Cloud Console
#   - gcloud CLI configured with appropriate permissions
#   - Service account created with required roles

set -euo pipefail

# Configuration
PROJECT_ID="nexusshield-prod"
REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
REGION="us-central1"
SERVICE_ACCOUNT="cloudbuild-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

log() { echo "[SETUP] $(date '+%H:%M:%S') $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }
success() { echo "[✓] $*"; }

log "Starting Cloud Build trigger setup for $REPO_OWNER/$REPO_NAME"

# Step 1: Verify repository connection exists
log "Step 1/4: Verifying Cloud Build repository connection..."
CONNECTIONS=$(gcloud builds connections list --project="$PROJECT_ID" --region="$REGION" --format=json 2>/dev/null || echo "[]")
if [ "$(echo "$CONNECTIONS" | jq 'length')" -eq 0 ]; then
  error "No Cloud Build repository connections found. Please complete manual setup:
    1. Go to Cloud Console: https://console.cloud.google.com/cloud-build/repositories
    2. Click 'Connect Repository'
    3. Select GitHub as provider
    4. Authorize GitHub app and select $REPO_OWNER/$REPO_NAME
    5. Re-run this script after connection is complete"
fi
success "Repository connection verified"

# Step 2: Create policy-check trigger
log "Step 2/4: Creating policy-check trigger..."
TRIGGER_NAME="policy-check-trigger"

if gcloud builds triggers list --project="$PROJECT_ID" --region="$REGION" \
  --filter="name=$TRIGGER_NAME" --format=json | jq -e '.[0]' &>/dev/null; then
  log "   Trigger $TRIGGER_NAME already exists, skipping"
else
  log "   Creating trigger..."
  gcloud builds triggers create github \
    --name="$TRIGGER_NAME" \
    --repo-owner="$REPO_OWNER" \
    --repo-name="$REPO_NAME" \
    --branch-pattern='^main$' \
    --build-config=cloudbuild/policy-check.yaml \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --service-account="projects/$PROJECT_ID/serviceAccounts/$SERVICE_ACCOUNT" \
    --include-logs-with-status \
    2>&1 | grep -E '(Created|already exists|Error)' || true
  success "Created $TRIGGER_NAME"
fi

# Step 3: Create direct-deploy trigger
log "Step 3/4: Creating direct-deploy trigger..."
TRIGGER_NAME="direct-deploy-trigger"

if gcloud builds triggers list --project="$PROJECT_ID" --region="$REGION" \
  --filter="name=$TRIGGER_NAME" --format=json | jq -e '.[0]' &>/dev/null; then
  log "   Trigger $TRIGGER_NAME already exists, skipping"
else
  log "   Creating trigger..."
  gcloud builds triggers create github \
    --name="$TRIGGER_NAME" \
    --repo-owner="$REPO_OWNER" \
    --repo-name="$REPO_NAME" \
    --branch-pattern='^main$' \
    --build-config=cloudbuild/direct-deploy.yaml \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --service-account="projects/$PROJECT_ID/serviceAccounts/$SERVICE_ACCOUNT" \
    --no-require-approval \
    --include-logs-with-status \
    2>&1 | grep -E '(Created|already exists|Error)' || true
  success "Created $TRIGGER_NAME"
fi

# Step 4: Verify triggers exist
log "Step 4/4: Verifying triggers..."
TRIGGERS=$(gcloud builds triggers list --project="$PROJECT_ID" --region="$REGION" --format=json)
POLICY_CHECK_EXISTS=$(echo "$TRIGGERS" | jq "any(.name == \"policy-check-trigger\")")
DIRECT_DEPLOY_EXISTS=$(echo "$TRIGGERS" | jq "any(.name == \"direct-deploy-trigger\")")

if [ "$POLICY_CHECK_EXISTS" = "true" ] && [ "$DIRECT_DEPLOY_EXISTS" = "true" ]; then
  success "All triggers created successfully"
  log ""
  log "============================================"
  log "✅ Cloud Build setup complete!"
  log "============================================"
  log ""
  log "Next steps:"
  log "  1. Push code to main branch to trigger policy-check"
  log "  2. Monitor builds: gcloud builds log --region=$REGION <BUILD_ID>"
  log "  3. View triggers: gcloud builds triggers list --region=$REGION"
  log ""
else
  log "Trigger status:"
  log "  policy-check-trigger: $POLICY_CHECK_EXISTS"
  log "  direct-deploy-trigger: $DIRECT_DEPLOY_EXISTS"
  error "Not all triggers could be created. Check Cloud Console for details."
fi
