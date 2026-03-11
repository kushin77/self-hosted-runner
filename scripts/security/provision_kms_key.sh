#!/usr/bin/env bash
set -euo pipefail

# Provisions GCP KMS keyring and key for encrypting mirrored credentials
# Idempotent: skips creation if keyring/key already exists
# Grants permissions to specified service account

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
REGION="${KMS_REGION:-us-central1}"
KEYRING_NAME="nexusshield"
KEY_NAME="mirror-key"
SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-nxs-portal-production-v2@nexusshield-prod.iam.gserviceaccount.com}"

DRY_RUN=false
GRANT_PERMS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --grant-perms)
      GRANT_PERMS=true
      shift
      ;;
    *)
      echo "Usage: $0 [--dry-run] [--grant-perms]"
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
  
  if ! gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q .; then
    log_error "No active gcloud authentication. Run: gcloud auth login"
    exit 1
  fi
}

create_keyring() {
  local keyring="$1"
  local region="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create keyring: $keyring (region: $region)"
    return 0
  fi
  
  if gcloud kms keyrings describe "$keyring" --location="$region" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_info "Keyring already exists: $keyring"
    return 0
  fi
  
  log_info "Creating KMS keyring: $keyring (region: $region)"
  gcloud kms keyrings create "$keyring" \
    --location="$region" \
    --project="$PROJECT_ID" || {
    log_error "Failed to create keyring: $keyring"
    return 1
  }
}

create_key() {
  local keyring="$1"
  local key="$2"
  local region="$3"
  local rotation_period="7776000s"  # 90 days
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create key: $key in keyring: $keyring"
    return 0
  fi
  
  if gcloud kms keys describe "$key" --location="$region" --keyring="$keyring" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_info "Key already exists: $key"
    return 0
  fi
  
  log_info "Creating KMS key: $key (with 90-day rotation)"
  gcloud kms keys create "$key" \
    --location="$region" \
    --keyring="$keyring" \
    --purpose="encryption" \
    --rotation-period="$rotation_period" \
    --next-rotation-time="$(date -u -d '+90 days' +%Y-%m-%dT00:00:00Z)" \
    --project="$PROJECT_ID" || {
    log_error "Failed to create key: $key"
    return 1
  }
}

grant_permissions() {
  local keyring="$1"
  local key="$2"
  local region="$3"
  local sa="$4"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would grant permissions to: $sa"
    return 0
  fi
  
  log_info "Granting permissions to service account: $sa"
  
  # Grant encrypt/decrypt permissions
  gcloud kms keys add-iam-policy-binding "$key" \
    --location="$region" \
    --keyring="$keyring" \
    --member="serviceAccount:$sa" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
    --project="$PROJECT_ID" \
    --quiet 2>/dev/null || log_warn "Failed to grant encrypter/decrypter role"
  
  # Grant viewer permissions
  gcloud kms keys add-iam-policy-binding "$key" \
    --location="$region" \
    --keyring="$keyring" \
    --member="serviceAccount:$sa" \
    --role="roles/cloudkms.viewer" \
    --project="$PROJECT_ID" \
    --quiet 2>/dev/null || log_warn "Failed to grant viewer role"
}

test_encryption() {
  local keyring="$1"
  local key="$2"
  local region="$3"
  local plaintext="test-secret-$(date +%s)"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would test KMS encryption"
    return 0
  fi
  
  log_info "Testing KMS encryption/decryption..."
  
  # Encrypt test data
  ciphertext=$(echo -n "$plaintext" | gcloud kms encrypt \
    --keyring="$keyring" \
    --key="$key" \
    --location="$region" \
    --plaintext-file=- \
    --ciphertext-file=- \
    --project="$PROJECT_ID" 2>/dev/null | base64 -w0)
  
  if [[ -z "$ciphertext" ]]; then
    log_error "Failed to encrypt test data"
    return 1
  fi
  
  # Decrypt test data
  decrypted=$(echo "$ciphertext" | base64 -d | gcloud kms decrypt \
    --keyring="$keyring" \
    --key="$key" \
    --location="$region" \
    --ciphertext-file=- \
    --plaintext-file=- \
    --project="$PROJECT_ID" 2>/dev/null)
  
  if [[ "$decrypted" == "$plaintext" ]]; then
    log_info "✓ KMS encryption/decryption test successful"
    return 0
  else
    log_error "KMS encryption/decryption test failed"
    return 1
  fi
}

# Main execution
log_info "Provisioning GCP KMS key (Project: $PROJECT_ID, Region: $REGION)"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN MODE] - No changes will be made"
fi

check_gcloud

# Create keyring and key
create_keyring "$KEYRING_NAME" "$REGION"
create_key "$KEYRING_NAME" "$KEY_NAME" "$REGION"

# Grant permissions if requested
if [[ "$GRANT_PERMS" == "true" ]]; then
  grant_permissions "$KEYRING_NAME" "$KEY_NAME" "$REGION" "$SERVICE_ACCOUNT"
fi

# Test encryption if not dry-run
if [[ "$DRY_RUN" != "true" ]]; then
  test_encryption "$KEYRING_NAME" "$KEY_NAME" "$REGION" || log_warn "Encryption test failed (but key may still be usable)"
fi

# Display key information
if [[ "$DRY_RUN" != "true" ]]; then
  log_info "Displaying KMS key details:"
  gcloud kms keys describe "$KEY_NAME" \
    --location="$REGION" \
    --keyring="$KEYRING_NAME" \
    --project="$PROJECT_ID" \
    --format="table(name,purpose,rotationSchedule.rotationPeriod,rotationSchedule.nextRotationTime)" || true
fi

log_info "Done. KMS key is ready for encrypting mirrored credentials."
log_info "Key resource name: projects/$PROJECT_ID/locations/$REGION/keyRings/$KEYRING_NAME/cryptoKeys/$KEY_NAME"
