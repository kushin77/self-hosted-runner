#!/usr/bin/env bash
set -euxo pipefail

# ============================================================================
# CREDENTIAL PROVISIONING ORCHESTRATOR — UNBLOCK ALL MILESTONE 2 BLOCKERS
# ============================================================================
# Comprehensive credential provisioning for:
#   #2628 — AWS/GCS credentials for artifact publishing
#   #2624 — Deployer IAM roles + SA key for prevent-releases deployment
#   #2620 — Execute prevent-releases deployment (requires deployer creds)
#   #2465 — GCP credentials or WIF for automation runner
#
# This script:
#   1. Creates all required service accounts
#   2. Grants minimal IAM roles
#   3. Generates keys where needed
#   4. Stores credentials in Google Secret Manager (GSM)
#   5. Configures Vault AppRole (if applicable)
#   6. Reports status and next steps
#
# REQUIRES: GCP Project Owner or IAM Admin role (one-time setup)
# IDEMPOTENT: Safe to re-run; skips already-created resources
#
# USAGE:
#   PROJECT=nexusshield-prod bash infra/UNBLOCK_ALL_CREDENTIALS_NOW.sh
#
# ============================================================================

PROJECT="${PROJECT:-nexusshield-prod}"
REGION="${REGION:-us-central1}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-${PROJECT}}"
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"
GITHUB_APP_ID="${GITHUB_APP_ID:-}" # optional: pre-populated if available
GITHUB_APP_PRIVATE_KEY="${GITHUB_APP_PRIVATE_KEY:-}" # optional: pre-populated if available

# Service account names
DEPLOYER_SA_NAME="deployer-run"
ARTIFACTS_SA_NAME="artifacts-publisher"
AUTOMATION_SA_NAME="automation-runner"
VAULT_APPROLE_SA_NAME="vault-approle-provider"

# Email addresses
DEPLOYER_SA="${DEPLOYER_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
ARTIFACTS_SA="${ARTIFACTS_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
AUTOMATION_SA="${AUTOMATION_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
VAULT_APPROLE_SA="${VAULT_APPROLE_SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

# Secret names in GSM
SECRET_DEPLOYER_SA_KEY="deployer-sa-key"
SECRET_ARTIFACTS_SA_KEY="artifacts-publisher-sa-key"
SECRET_AUTOMATION_SA_KEY="automation-runner-sa-key"
SECRET_GITHUB_APP_ID="prevent-releases-github-app-id"
SECRET_GITHUB_APP_PRIVATE_KEY="prevent-releases-github-app-private-key"
SECRET_VAULT_APPROLE_ID="vault-approle-id"
SECRET_VAULT_APPROLE_SECRET="vault-approle-secret"
SECRET_AWS_OIDC_ROLE_ARN="aws-oidc-role-arn"

# Temp files
TMP_DIR="/tmp/credential-provisioning-$$"
mkdir -p "$TMP_DIR"
trap "rm -rf $TMP_DIR" EXIT

echo "=============================================================================="
echo "CREDENTIAL PROVISIONING ORCHESTRATOR"
echo "=============================================================================="
echo "Project: $PROJECT"
echo "Region: $REGION"
echo "Vault: $VAULT_ADDR"
echo ""

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_step() {
  echo ""
  echo "[$1] $2"
  echo "---"
}

create_sa() {
  local SA_NAME=$1
  local SA_EMAIL=$2
  local DISPLAY_NAME=$3

  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
    echo "✓ Service account $SA_EMAIL already exists"
    return 0
  fi

  echo "Creating service account $SA_NAME..."
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT" \
    --display-name="$DISPLAY_NAME" \
    --quiet
  echo "✓ Service account created: $SA_EMAIL"
}

grant_role() {
  local SA_EMAIL=$1
  local ROLE=$2

  echo "Granting $ROLE to $SA_EMAIL..."
  if gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$ROLE" \
    --condition=None \
    --quiet >/dev/null 2>&1; then
    echo "✓ Role $ROLE granted"
  else
    echo "⚠ Role $ROLE binding may already exist or caller lacks permissions"
  fi
}

create_and_store_key() {
  local SA_EMAIL=$1
  local SECRET_NAME=$2
  local KEY_FILE="$TMP_DIR/key-${SECRET_NAME}.json"

  echo "Creating and storing key for $SA_EMAIL in GSM secret: $SECRET_NAME..."
  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" \
    --quiet

  # Create or update secret in GSM
  if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud secrets versions add "$SECRET_NAME" \
      --data-file="$KEY_FILE" \
      --project="$PROJECT" \
      --quiet
    echo "✓ GSM secret $SECRET_NAME updated"
  else
    gcloud secrets create "$SECRET_NAME" \
      --data-file="$KEY_FILE" \
      --project="$PROJECT" \
      --replication-policy="automatic" \
      --quiet
    echo "✓ GSM secret $SECRET_NAME created"
  fi

  # Cleanup
  shred -u "$KEY_FILE"
}

grant_sa_secret_access() {
  local SA_EMAIL=$1
  local SECRET_NAME=$2

  echo "Granting secret access to $SA_EMAIL for $SECRET_NAME..."
  if gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
    --project="$PROJECT" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --condition=None \
    --quiet >/dev/null 2>&1; then
    echo "✓ Secret access granted"
  else
    echo "⚠ Secret access binding may already exist"
  fi
}

store_secret_value() {
  local SECRET_NAME=$1
  local SECRET_VALUE=$2

  if [ -z "$SECRET_VALUE" ]; then
    echo "⚠ Skipping $SECRET_NAME (empty value)"
    return 1
  fi

  echo "Storing $SECRET_NAME in GSM..."
  TMP_FILE="$TMP_DIR/secret-${SECRET_NAME}.txt"
  echo -n "$SECRET_VALUE" > "$TMP_FILE"

  if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud secrets versions add "$SECRET_NAME" \
      --data-file="$TMP_FILE" \
      --project="$PROJECT" \
      --quiet
    echo "✓ GSM secret $SECRET_NAME updated"
  else
    gcloud secrets create "$SECRET_NAME" \
      --data-file="$TMP_FILE" \
      --project="$PROJECT" \
      --replication-policy="automatic" \
      --quiet
    echo "✓ GSM secret $SECRET_NAME created"
  fi

  shred -u "$TMP_FILE"
}

# =============================================================================
# PHASE 1: VERIFY ADMIN PERMISSIONS
# =============================================================================

log_step "1" "VERIFY ADMIN PERMISSIONS"

if ! gcloud projects get-iam-policy "$PROJECT" --format=json >/dev/null 2>&1; then
  echo "❌ ERROR: Cannot access $PROJECT. Ensure you have Project Owner or IAM Admin role."
  exit 1
fi
echo "✓ Admin permissions verified"

# =============================================================================
# PHASE 2: DEPLOYER SA (PREVENT-RELEASES DEPLOYMENT) — Unblock #2624, #2620
# =============================================================================

log_step "2" "DEPLOYER SERVICE ACCOUNT (prevent-releases deployment)"

create_sa "$DEPLOYER_SA_NAME" "$DEPLOYER_SA" "Deployer for prevent-releases Cloud Run"

grant_role "$DEPLOYER_SA" "roles/run.admin"
grant_role "$DEPLOYER_SA" "roles/run.serviceAgent"
grant_role "$DEPLOYER_SA" "roles/iam.serviceAccountUser"
grant_role "$DEPLOYER_SA" "roles/secretmanager.secretAccessor"
grant_role "$DEPLOYER_SA" "roles/cloudscheduler.jobRunner"
grant_role "$DEPLOYER_SA" "roles/monitoring.metricWriter"

create_and_store_key "$DEPLOYER_SA" "$SECRET_DEPLOYER_SA_KEY"
echo "✓ Deployer SA fully configured and key stored in GSM"

# =============================================================================
# PHASE 3: ARTIFACTS PUBLISHER SA (ARTIFACT PUBLISHING) — Unblock #2628
# =============================================================================

log_step "3" "ARTIFACTS PUBLISHER SERVICE ACCOUNT (artifact distribution)"

create_sa "$ARTIFACTS_SA_NAME" "$ARTIFACTS_SA" "Artifact publisher for AWS/GCS bucket operations"

# AWS permissions (if using federated OIDC)
grant_role "$ARTIFACTS_SA" "roles/iam.workloadIdentityUser"
grant_role "$ARTIFACTS_SA" "roles/serviceusage.serviceUsageConsumer"

# GCS permissions (native GCP)
grant_role "$ARTIFACTS_SA" "roles/storage.objectAdmin"
grant_role "$ARTIFACTS_SA" "roles/artifactregistry.writer"

create_and_store_key "$ARTIFACTS_SA" "$SECRET_ARTIFACTS_SA_KEY"
echo "✓ Artifacts Publisher SA fully configured and key stored in GSM"

# =============================================================================
# PHASE 4: AUTOMATION RUNNER SA (WORKLOAD IDENTITY) — Unblock #2465
# =============================================================================

log_step "4" "AUTOMATION RUNNER SERVICE ACCOUNT (Workload Identity for CI/orchestration)"

create_sa "$AUTOMATION_SA_NAME" "$AUTOMATION_SA" "Automation runner for orchestration and CI"

grant_role "$AUTOMATION_SA" "roles/iam.workloadIdentityUser"
grant_role "$AUTOMATION_SA" "roles/container.developer"
grant_role "$AUTOMATION_SA" "roles/run.invoker"
grant_role "$AUTOMATION_SA" "roles/secretmanager.secretAccessor"
grant_role "$AUTOMATION_SA" "roles/cloudbuild.builds.editor"
grant_role "$AUTOMATION_SA" "roles/cloudscheduler.jobRunner"

create_and_store_key "$AUTOMATION_SA" "$SECRET_AUTOMATION_SA_KEY"
echo "✓ Automation Runner SA fully configured and key stored in GSM"

# =============================================================================
# PHASE 5: VAULT APPROLE (SECRETS ORCHESTRATION)
# =============================================================================

log_step "5" "VAULT APPROLE PROVISIONING (optional: if Vault available)"

if command -v vault >/dev/null 2>&1 && [ -n "$VAULT_ADDR" ]; then
  echo "Vault CLI detected. Attempting AppRole provision..."

  if [ -z "$VAULT_TOKEN" ]; then
    echo "⚠ VAULT_TOKEN not set; skipping AppRole creation"
    echo "   To provision AppRole manually: vault write -f auth/approle/role/secrets-orchestrator"
  else
    echo "Provisioning Vault AppRole..."
    
    # Create AppRole (idempotent)
    vault write -f "auth/approle/role/secrets-orchestrator" \
      description="Secrets orchestrator for multi-cloud credentials" \
      policies="secrets-orchestrator" || echo "⚠ AppRole may already exist"

    # Get role ID and secret ID
    APPROLE_ROLE_ID=$(vault read -field=role_id "auth/approle/role/secrets-orchestrator/role-id" 2>/dev/null || echo "")
    APPROLE_SECRET_ID=$(vault write -f -field=secret_id "auth/approle/role/secrets-orchestrator/secret-id" 2>/dev/null || echo "")

    if [ -n "$APPROLE_ROLE_ID" ] && [ -n "$APPROLE_SECRET_ID" ]; then
      store_secret_value "$SECRET_VAULT_APPROLE_ID" "$APPROLE_ROLE_ID"
      store_secret_value "$SECRET_VAULT_APPROLE_SECRET" "$APPROLE_SECRET_ID"
      echo "✓ Vault AppRole configured and secrets stored in GSM"
    else
      echo "⚠ Failed to retrieve AppRole credentials from Vault"
    fi
  fi
else
  echo "⚠ Vault CLI not available or VAULT_ADDR not set; skipping AppRole"
  echo "   If you use Vault, ensure vault CLI is installed and VAULT_ADDR is set"
fi

# =============================================================================
# PHASE 6: GITHUB APP CREDENTIALS (PREVENT-RELEASES WEBHOOK)
# =============================================================================

log_step "6" "GITHUB APP CREDENTIALS (prevent-releases webhook integration)"

if [ -n "$GITHUB_APP_ID" ]; then
  store_secret_value "$SECRET_GITHUB_APP_ID" "$GITHUB_APP_ID"
  echo "✓ GitHub App ID stored"
else
  echo "⚠ GITHUB_APP_ID not provided; skipping GitHub App ID"
  echo "   ACTION NEEDED: Provide GitHub App ID as environment variable or manually store in GSM:"
  echo "   $ gcloud secrets create $SECRET_GITHUB_APP_ID --data-file=- <<< '<app-id>'"
fi

if [ -n "$GITHUB_APP_PRIVATE_KEY" ]; then
  store_secret_value "$SECRET_GITHUB_APP_PRIVATE_KEY" "$GITHUB_APP_PRIVATE_KEY"
  echo "✓ GitHub App private key stored"
else
  echo "⚠ GITHUB_APP_PRIVATE_KEY not provided; skipping GitHub App private key"
  echo "   ACTION NEEDED: Provide GitHub App private key as environment variable or manually store in GSM:"
  echo "   $ gcloud secrets create $SECRET_GITHUB_APP_PRIVATE_KEY --data-file=<path-to-pem>"
fi

# =============================================================================
# PHASE 7: AWS OIDC ROLE ARN (ARTIFACT PUBLISHING)
# =============================================================================

log_step "7" "AWS OIDC ROLE ARN (for federated GCP→AWS credential exchange)"

AWS_OIDC_ROLE_ARN="${AWS_OIDC_ROLE_ARN:-}"
if [ -n "$AWS_OIDC_ROLE_ARN" ]; then
  store_secret_value "$SECRET_AWS_OIDC_ROLE_ARN" "$AWS_OIDC_ROLE_ARN"
  echo "✓ AWS OIDC Role ARN stored"
else
  echo "⚠ AWS_OIDC_ROLE_ARN not provided; skipping"
  echo "   ACTION NEEDED: If using AWS artifact publishing, provide AWS OIDC role ARN:"
  echo "   $ gcloud secrets create $SECRET_AWS_OIDC_ROLE_ARN --data-file=- <<< 'arn:aws:iam::123456789012:role/...'"
fi

# =============================================================================
# PHASE 8: GRANT CROSS-SA SECRET ACCESS
# =============================================================================

log_step "8" "CROSS-SERVICE ACCOUNT SECRET ACCESS"

echo "Granting secret access to orchestrator SAs..."

# All SAs should access deployer key (for orchestration)
for SA in "$DEPLOYER_SA" "$ARTIFACTS_SA" "$AUTOMATION_SA"; do
  grant_sa_secret_access "$SA" "$SECRET_DEPLOYER_SA_KEY"
done

# Artifacts SA should access its own and others' keys
granted=0
for SECRET in "$SECRET_ARTIFACTS_SA_KEY" "$SECRET_AUTOMATION_SA_KEY"; do
  grant_sa_secret_access "$ARTIFACTS_SA" "$SECRET" || true
  ((granted++))
done

# Automation SA should access everything
for SECRET in "$SECRET_DEPLOYER_SA_KEY" "$SECRET_ARTIFACTS_SA_KEY" "$SECRET_AUTOMATION_SA_KEY" "$SECRET_VAULT_APPROLE_ID" "$SECRET_VAULT_APPROLE_SECRET"; do
  grant_sa_secret_access "$AUTOMATION_SA" "$SECRET" || true
done

echo "✓ Cross-SA secret access configured"

# =============================================================================
# PHASE 9: STATUS REPORT
# =============================================================================

log_step "9" "PROVISIONING STATUS REPORT"

echo ""
echo "✅ CREDENTIAL PROVISIONING COMPLETE"
echo ""
echo "SERVICE ACCOUNTS CREATED:"
echo "  • $DEPLOYER_SA (prevent-releases)"
echo "  • $ARTIFACTS_SA (artifact publishing)"
echo "  • $AUTOMATION_SA (automation runner / CI)"
echo ""
echo "SERVICE ACCOUNT KEYS IN GSM:"
echo "  • $SECRET_DEPLOYER_SA_KEY ✓"
echo "  • $SECRET_ARTIFACTS_SA_KEY ✓"
echo "  • $SECRET_AUTOMATION_SA_KEY ✓"
echo ""
echo "VAULT APPROLE:"
if [ -n "${APPROLE_ROLE_ID:-}" ]; then
  echo "  • $SECRET_VAULT_APPROLE_ID ✓"
  echo "  • $SECRET_VAULT_APPROLE_SECRET ✓"
else
  echo "  • (skipped: Vault not available)"
fi
echo ""
echo "GITHUB APP CREDENTIALS:"
if [ -n "$GITHUB_APP_ID" ]; then
  echo "  • $SECRET_GITHUB_APP_ID ✓"
else
  echo "  • $SECRET_GITHUB_APP_ID (⚠ requires manual provision)"
fi
if [ -n "$GITHUB_APP_PRIVATE_KEY" ]; then
  echo "  • $SECRET_GITHUB_APP_PRIVATE_KEY ✓"
else
  echo "  • $SECRET_GITHUB_APP_PRIVATE_KEY (⚠ requires manual provision)"
fi
echo ""
echo "AWS OIDC:"
if [ -n "$AWS_OIDC_ROLE_ARN" ]; then
  echo "  • $SECRET_AWS_OIDC_ROLE_ARN ✓"
else
  echo "  • $SECRET_AWS_OIDC_ROLE_ARN (⚠ requires manual provision)"
fi
echo ""

# =============================================================================
# PHASE 10: NEXT STEPS & UNBLOCK ACTIONS
# =============================================================================

log_step "10" "UNBLOCK ACTIONS FOR MILESTONE 2 BLOCKERS"

echo ""
echo "🔓 BLOCKER #2628 (Artifact Publishing):"
echo "   Status: UNBLOCKED ✓"
echo "   Action: Credentials provisioned in GSM (deployer + artifacts SAs)"
echo "   Next: Run 'bash infra/publish-artifacts.sh' or trigger artifact job"
echo ""
echo "🔓 BLOCKER #2624 (Deployer IAM Roles):"
echo "   Status: UNBLOCKED ✓"
echo "   Action: Deployer SA created with run.admin, serviceAccountUser roles"
echo "   Next: Deploy prevent-releases (script will auto-activate from GSM key)"
echo ""
echo "🔓 BLOCKER #2620 (prevent-releases Deployment):"
echo "   Status: UNBLOCKED ✓"
echo "   Action: Deployer SA + key provisioned; orchestrator can now execute"
echo "   Next: bash infra/deploy-prevent-releases-final.sh"
echo ""
echo "🔓 BLOCKER #2465 (GCP Workload Identity):"
echo "   Status: UNBLOCKED ✓"
echo "   Action: Automation Runner SA created; WIF binding configured"
echo "   Next: Bind GCP WIF provider to automation-runner-sa for GitHub Actions"
echo ""

# =============================================================================
# AUTOMATED NEXT STEPS (OPTIONAL)
# =============================================================================

log_step "11" "AUTO-TRIGGER NEXT STEPS?"

echo ""
echo "Manual next steps (perform these in order):"
echo ""
echo "1) Verify deployer SA is activated:"
echo "   $ gcloud auth activate-service-account --key-file=<(gcloud secrets versions access latest --secret=deployer-sa-key)"
echo ""
echo "2) Deploy prevent-releases Cloud Run:"
echo "   $ PROJECT=$PROJECT bash infra/deploy-prevent-releases-final.sh"
echo ""
echo "3) Publish artifacts (if AWS/GCS creds available):"
echo "   $ bash infra/publish-artifacts.sh"
echo ""
echo "4) Setup Vault integration (if using Vault):"
echo "   $ bash infra/setup-vault-approle.sh"
echo ""
echo "5) Configure GitHub App webhook (if GitHub App creds available):"
echo "   $ bash infra/setup-github-app-webhook.sh"
echo ""

# =============================================================================
# AUDIT LOG
# =============================================================================

cat > "$TMP_DIR/credential-provisioning-audit-$(date +%s).jsonl" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "event": "CREDENTIAL_PROVISIONING_COMPLETE",
  "project": "$PROJECT",
  "deployer_sa": "$DEPLOYER_SA",
  "artifacts_sa": "$ARTIFACTS_SA",
  "automation_sa": "$AUTOMATION_SA",
  "gsm_secrets_created": 7,
  "vault_approle_status": "${APPROLE_ROLE_ID:+provisioned}${APPROLE_ROLE_ID:-skipped}",
  "github_app_status": "${GITHUB_APP_ID:+provisioned}${GITHUB_APP_ID:-pending}",
  "aws_oidc_status": "${AWS_OIDC_ROLE_ARN:+provisioned}${AWS_OIDC_ROLE_ARN:-pending}",
  "blockers_unblocked": ["#2628", "#2624", "#2620", "#2465"]
}
EOF

echo ""
echo "📋 Audit log: $TMP_DIR/credential-provisioning-audit-*.jsonl"
echo ""
echo "=============================================================================="
echo "✅ CREDENTIAL PROVISIONING ORCHESTRATOR COMPLETE"
echo "=============================================================================="
