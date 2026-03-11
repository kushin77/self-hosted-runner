#!/usr/bin/env bash
set -euo pipefail

# Backs up sensitive local files to Google Secret Manager and creates monitoring secrets
# Idempotent: safe to re-run. Will update existing secrets.

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-nxs-portal-production-v2@nexusshield-prod.iam.gserviceaccount.com}"

# Secrets to create (name -> value or file path)
declare -A SECRETS=(
  ["slack-integration-webhook"]="${SLACK_WEBHOOK_URL:-https://hooks.slack.com/services/REPLACE_WITH_WEBHOOK}"
  ["pagerduty-integration-key"]="${PAGERDUTY_INTEGRATION_KEY:-REPLACE_WITH_PAGERDUTY_KEY}"
)

# Files to back up to GSM (path -> secret_name)
declare -A FILE_BACKUPS=(
  [".credentials/gcp-service-account.json"]="gcp-service-account-backup"
  [".credentials/vault-token"]="vault-token-backup"
  [".credentials/aws-credentials"]="aws-credentials-backup"
)

DRY_RUN=false
PUSH_FILE=false

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --push-file)
      PUSH_FILE=true
      shift
      ;;
    *)
      echo "Usage: $0 [--dry-run] [--push-file]"
      exit 1
      ;;
  esac
done

log_info() {
  echo "[INFO] $*" >&2
}

log_warn() {
  echo "[WARN] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

check_gcloud() {
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found. Install it first."
    exit 1
  fi
  
  # Verify authentication
  if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
    log_error "No active gcloud authentication. Run: gcloud auth login"
    exit 1
  fi
}

create_or_update_secret() {
  local secret_name="$1"
  local secret_value="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create/update secret: $secret_name"
    return 0
  fi
  
  # Check if secret exists
  if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null; then
    log_info "Updating existing secret: $secret_name"
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
      --project="$PROJECT_ID" \
      --data-file=- 2>/dev/null || {
      log_error "Failed to update secret: $secret_name"
      return 1
    }
  else
    log_info "Creating new secret: $secret_name"
    echo -n "$secret_value" | gcloud secrets create "$secret_name" \
      --project="$PROJECT_ID" \
      --replication-policy="automatic" \
      --data-file=- 2>/dev/null || {
      log_error "Failed to create secret: $secret_name"
      return 1
    }
  fi
  
  # Grant service account access to secret
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet 2>/dev/null || {
    log_warn "Could not grant IAM permissions to $SERVICE_ACCOUNT for $secret_name"
  }
}

backup_file_to_gsm() {
  local file_path="$1"
  local secret_name="$2"
  
  if [[ ! -f "$file_path" ]]; then
    log_warn "File not found, skipping backup: $file_path"
    return 0
  fi
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would back up file to secret: $file_path -> $secret_name"
    return 0
  fi
  
  log_info "Backing up $file_path to GSM secret: $secret_name"
  
  if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null; then
    gcloud secrets versions add "$secret_name" \
      --project="$PROJECT_ID" \
      --data-file="$file_path" 2>/dev/null || {
      log_error "Failed to update secret: $secret_name"
      return 1
    }
  else
    gcloud secrets create "$secret_name" \
      --project="$PROJECT_ID" \
      --replication-policy="automatic" \
      --data-file="$file_path" 2>/dev/null || {
      log_error "Failed to create secret: $secret_name"
      return 1
    }
  fi
  
  # Grant access
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project="$PROJECT_ID" \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet 2>/dev/null || true
}

grant_permissions() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would grant permissions to service account: $SERVICE_ACCOUNT"
    return 0
  fi
  
  log_info "Granting permissions to service account: $SERVICE_ACCOUNT"
  
  local roles=(
    "roles/secretmanager.admin"
    "roles/secretmanager.secretAccessor"
  )
  
  for role in "${roles[@]}"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SERVICE_ACCOUNT" \
      --role="$role" \
      --quiet 2>/dev/null || log_warn "Failed to grant $role"
  done
}

# Main execution
log_info "Backing up secrets to GSM (Project: $PROJECT_ID)"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN MODE] - No changes will be made"
fi

check_gcloud

# Create/update main secrets
log_info "Processing integration secrets..."
for secret_name in "${!SECRETS[@]}"; do
  secret_value="${SECRETS[$secret_name]}"
  create_or_update_secret "$secret_name" "$secret_value"
done

# Back up sensitive files if requested
if [[ "$PUSH_FILE" == "true" ]]; then
  log_info "Backing up local sensitive files..."
  for file_path in "${!FILE_BACKUPS[@]}"; do
    secret_name="${FILE_BACKUPS[$file_path]}"
    backup_file_to_gsm "$file_path" "$secret_name"
  done
else
  log_info "Skipping file backups (use --push-file to enable)"
fi

# Grant permissions to service account
grant_permissions

# List created/updated secrets
if [[ "$DRY_RUN" != "true" ]]; then
  log_info "Listing secrets in GSM:"
  gcloud secrets list --project="$PROJECT_ID" --format='table(name,created,updated)' 2>/dev/null || true
fi

log_info "Done. Secrets are now available in GSM for monitoring automation."
