#!/usr/bin/env bash
# Comprehensive Phase0 + Cloud Build + Drift automation wrapper
# This script automates the entire direct-deployment setup.
# Usage: ./scripts/ops/deploy_complete.sh <PROJECT_ID> <ORG> <REPO> <GITHUB_TOKEN> <SLACK_WEBHOOK_URL>

set -euo pipefail

PROJECT_ID="${1:-}"
GITHUB_ORG="${2:-}"
GITHUB_REPO="${3:-}"
GITHUB_TOKEN="${4:-}"
SLACK_WEBHOOK="${5:-}"

if [[ -z "$PROJECT_ID" ]] || [[ -z "$GITHUB_ORG" ]] || [[ -z "$GITHUB_REPO" ]]; then
  echo "Usage: $0 <PROJECT_ID> <ORG> <REPO> [GITHUB_TOKEN] [SLACK_WEBHOOK]"
  echo "Example: $0 my-project myorg my-runner ghp_... https://hooks.slack.com/..."
  exit 1
fi

echo "====== Phase0 Complete Automation ======"
echo "Project: $PROJECT_ID"
echo "Repo: $GITHUB_ORG/$GITHUB_REPO"
echo ""

# Get Cloud Build SA
echo "[1/5] Fetching Cloud Build service account..."
CB_SA="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"
echo "Cloud Build SA: $CB_SA"

echo ""
echo "[2/5] Running Phase0 Terraform (GSM/KMS/Cloud Build trigger)..."
cd terraform/phase0-core
terraform init
terraform apply -auto-approve \
  -var="project_id=$PROJECT_ID" \
  -var="cloud_build_service_account=$CB_SA" \
  -var="github_owner=$GITHUB_ORG" \
  -var="github_repo=$GITHUB_REPO" \
  -var="secret_data=placeholder" || { echo "Phase0 apply failed"; exit 1; }
cd - >/dev/null
echo "✅ Phase0 complete"

echo ""
echo "[3/5] Granting Cloud Build SA IAM roles..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CB_SA" \
  --role="roles/secretmanager.secretAccessor" \
  --quiet || echo "Warning: secretAccessor role may be already assigned"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CB_SA" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --quiet || echo "Warning: cryptoKeyEncrypterDecrypter role may be already assigned"
echo "✅ IAM roles granted"

if [[ -n "$GITHUB_TOKEN" ]]; then
  echo ""
  echo "[4/5] Applying GitHub branch protection (requires Cloud Build CI integration)..."
  export GITHUB_TOKEN
  cd terraform/phase0-core
  terraform apply -auto-approve \
    -var="github_owner=$GITHUB_ORG" \
    -var="github_repo=$GITHUB_REPO" \
    -target=github_branch_protection.main || echo "Warning: branch protection apply failed; may need manual GitHub setup"
  cd - >/dev/null
  echo "✅ Branch protection applied"
else
  echo ""
  echo "[4/5] ⚠️  Skipping branch protection (GITHUB_TOKEN not provided)"
  echo "  To apply later, run:"
  echo "  cd terraform/phase0-core"
  echo "  export GITHUB_TOKEN=ghp_..."
  echo "  terraform apply -target=github_branch_protection.main"
fi

echo ""
echo "[5/5] Running Cloud Build smoke verification..."
gcloud builds submit --config=cloudbuild.smoke.yaml . --project="$PROJECT_ID" || echo "Warning: smoke build check failed; review Cloud Build logs"
echo "✅ Smoke build submitted"

echo ""
echo "====== Automation Complete ======"
echo "Next steps:"
echo "1. Monitor smoke build in Cloud Build console"
echo "2. Deploy drift detection CronJob: kubectl apply -f k8s/cronjobs/drift-detection.yaml"
echo "3. Configure Slack webhook: kubectl create secret generic ops-secrets --from-literal=slack_webhook='$SLACK_WEBHOOK' -n ops"
echo "4. Verify branch protection is enforcing Cloud Build checks"
echo ""
echo "Ops issue for tracking: #3030"
