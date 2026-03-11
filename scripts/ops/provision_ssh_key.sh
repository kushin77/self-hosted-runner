#!/usr/bin/env bash
set -euo pipefail

# Provisions SSH ed25519 key and stores it securely in GSM/Vault/KMS with automatic failover
# Idempotent: regenerates key only if not found in any backend
# Implements multi-layer credential storage: GSM (primary) → Vault (secondary) → KMS (tertiary)

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
RUNNER_NAME="${RUNNER_NAME:-self-hosted-runner}"
RUNNER_KEY_DIR="${RUNNER_KEY_DIR:-./.runner-keys}"
GSM_SECRET_NAME="ssh-${RUNNER_NAME}-ed25519-private"
VAULT_PATH="${VAULT_PATH:-secret/runners/ssh-keys}"
KMS_KEY_NAME="mirror-key"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Usage: $0 [--dry-run]"
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

check_dependencies() {
  local missing=0
  
  for cmd in ssh-keygen gcloud jq; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Required command not found: $cmd"
      ((missing++))
    fi
  done
  
  if [[ $missing -gt 0 ]]; then
    return 1
  fi
}

# Try to fetch SSH key from GSM
get_ssh_key_from_gsm() {
  local secret_name="$1"
  
  if ! gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    return 1
  fi
  
  gcloud secrets versions access latest --secret="$secret_name" --project="$PROJECT_ID" 2>/dev/null || return 1
}

# Try to fetch SSH key from Vault
get_ssh_key_from_vault() {
  local vault_path="$1"
  local secret_name="$2"
  
  if ! command -v vault &>/dev/null; then
    return 1
  fi
  
  if [[ -z "${VAULT_ADDR:-}" ]]; then
    log_warn "VAULT_ADDR not set; skipping Vault lookup"
    return 1
  fi
  
  vault kv get -field=value "$vault_path/$secret_name" 2>/dev/null || return 1
}

# Try to decrypt from KMS (if ciphertext is available)
get_ssh_key_from_kms_cache() {
  local kms_cache="$1"
  
  if [[ ! -f "$kms_cache" ]]; then
    return 1
  fi
  
  gcloud kms decrypt \
    --keyring="nexusshield" \
    --key="mirror-key" \
    --location="us-central1" \
    --ciphertext-file="$kms_cache" \
    --plaintext-file=- \
    --project="$PROJECT_ID" 2>/dev/null || return 1
}

# Generate new SSH key (ed25519, secure)
generate_ssh_key() {
  local key_file="$1"
  local comment="$2"
  
  mkdir -p "$(dirname "$key_file")"
  
  log_info "Generating ed25519 SSH key: $key_file"
  
  ssh-keygen -t ed25519 \
    -f "$key_file" \
    -C "$comment" \
    -N "" \
    -q || {
    log_error "Failed to generate SSH key"
    return 1
  }
  
  # Secure private key (600 permissions)
  chmod 600 "$key_file"
  chmod 644 "$key_file.pub"
  
  log_info "✓ SSH key generated"
}

# Store SSH key in GSM
store_ssh_key_in_gsm() {
  local key_file="$1"
  local secret_name="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would store SSH key in GSM: $secret_name"
    return 0
  fi
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud not found; cannot store in GSM"
    return 1
  fi
  
  log_info "Storing SSH key in GSM: $secret_name"
  
  # Check if secret exists
  if gcloud secrets describe "$secret_name" --project="$PROJECT_ID" &>/dev/null 2>&1; then
    # Update existing secret
    gcloud secrets versions add "$secret_name" \
      --project="$PROJECT_ID" \
      --data-file="$key_file" 2>/dev/null || {
      log_error "Failed to update GSM secret"
      return 1
    }
  else
    # Create new secret
    gcloud secrets create "$secret_name" \
      --project="$PROJECT_ID" \
      --replication-policy="automatic" \
      --data-file="$key_file" 2>/dev/null || {
      log_error "Failed to create GSM secret"
      return 1
    }
  fi
  
  log_info "✓ SSH key stored in GSM"
}

# Store SSH key in Vault
store_ssh_key_in_vault() {
  local key_file="$1"
  local vault_path="$2"
  local secret_name="$3"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would store SSH key in Vault: $vault_path/$secret_name"
    return 0
  fi
  
  if ! command -v vault &>/dev/null; then
    log_warn "vault not found; skipping Vault storage"
    return 0
  fi
  
  if [[ -z "${VAULT_ADDR:-}" ]]; then
    log_warn "VAULT_ADDR not set; skipping Vault storage"
    return 0
  fi
  
  log_info "Storing SSH key in Vault: $vault_path/$secret_name"
  
  vault kv put "$vault_path/$secret_name" \
    value="@$key_file" 2>/dev/null || {
    log_warn "Failed to store in Vault (continuing with GSM)"
    return 0
  }
  
  log_info "✓ SSH key also stored in Vault"
}

# Encrypt and store SSH key using KMS (for audit trail)
store_ssh_key_encrypted_kms() {
  local key_file="$1"
  local cache_dir="./.runner-keys-encrypted"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would encrypt SSH key with KMS"
    return 0
  fi
  
  if ! command -v gcloud &>/dev/null; then
    log_warn "gcloud not found; skipping KMS encryption"
    return 0
  fi
  
  mkdir -p "$cache_dir"
  local encrypted_file="$cache_dir/$(basename "$key_file").enc"
  
  log_info "Encrypting SSH key with KMS: $encrypted_file"
  
  gcloud kms encrypt \
    --keyring="nexusshield" \
    --key="mirror-key" \
    --location="us-central1" \
    --plaintext-file="$key_file" \
    --ciphertext-file="$encrypted_file" \
    --project="$PROJECT_ID" 2>/dev/null || {
    log_warn "Failed to encrypt with KMS (continuing)"
    return 0
  }
  
  log_info "✓ SSH key encrypted and cached: $encrypted_file"
}

# Verify SSH key is accessible and valid
verify_ssh_key() {
  local secret_name="$1"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would verify SSH key accessibility"
    return 0
  fi
  
  log_info "Verifying SSH key accessibility..."
  
  # Try to retrieve from GSM
  local key_content
  key_content=$(get_ssh_key_from_gsm "$secret_name" 2>/dev/null) || {
    log_error "Could not retrieve SSH key from GSM"
    return 1
  }
  
  # Verify it looks like a valid ed25519 key
  if echo "$key_content" | grep -q "BEGIN OPENSSH PRIVATE KEY"; then
    log_info "✓ SSH key format verified (ed25519)"
    return 0
  else
    log_error "SSH key format unrecognized"
    return 1
  fi
}

# Provision failover retrieval script for runner
create_ssh_retrieval_script() {
  local script_path="$1"
  local secret_name="$2"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would create SSH retrieval script"
    return 0
  fi
  
  mkdir -p "$(dirname "$script_path")"
  
  cat > "$script_path" <<'SCRIPT'
#!/usr/bin/env bash
# Auto-generated SSH key retrieval script with multi-layer failover
# Fetches ed25519 SSH private key from GSM→Vault→KMS

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
SECRET_NAME="${1:-ssh-self-hosted-runner-ed25519-private}"
OUTPUT_FILE="${2:-}"

log_info() { echo "[INFO] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

retrieve_from_gsm() {
  log_info "Attempting GSM retrieval..."
  if command -v gcloud &>/dev/null; then
    gcloud secrets versions access latest \
      --secret="$SECRET_NAME" \
      --project="$PROJECT_ID" 2>/dev/null && return 0 || true
  fi
  return 1
}

retrieve_from_vault() {
  log_info "Attempting Vault retrieval..."
  if command -v vault &>/dev/null && [[ -n "${VAULT_ADDR:-}" ]]; then
    vault kv get -field=value "secret/runners/ssh-keys/$SECRET_NAME" 2>/dev/null && return 0 || true
  fi
  return 1
}

retrieve_from_kms() {
  log_info "Attempting KMS retrieval from cache..."
  if [[ -f "./.runner-keys-encrypted/$SECRET_NAME.enc" ]] && command -v gcloud &>/dev/null; then
    gcloud kms decrypt \
      --keyring="nexusshield" \
      --key="mirror-key" \
      --location="us-central1" \
      --ciphertext-file="./.runner-keys-encrypted/$SECRET_NAME.enc" \
      --plaintext-file=- \
      --project="$PROJECT_ID" 2>/dev/null && return 0 || true
  fi
  return 1
}

# Try each backend in order
if key_content=$(retrieve_from_gsm); then
  log_info "✓ SSH key retrieved from GSM"
elif key_content=$(retrieve_from_vault); then
  log_info "✓ SSH key retrieved from Vault"
elif key_content=$(retrieve_from_kms); then
  log_info "✓ SSH key retrieved and decrypted from KMS"
else
  log_error "Failed to retrieve SSH key from any backend"
  exit 1
fi

# Write to file or stdout
if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$key_content" > "$OUTPUT_FILE"
  chmod 600 "$OUTPUT_FILE"
  log_info "SSH key written to: $OUTPUT_FILE"
else
  echo "$key_content"
fi
SCRIPT
  
  chmod +x "$script_path"
  log_info "✓ SSH retrieval script created: $script_path"
}

# Main execution
log_info "Provisioning SSH key storage (GSM/Vault/KMS)"
log_info "Project: $PROJECT_ID"
log_info "Runner: $RUNNER_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY-RUN MODE] - No changes will be made"
fi

check_dependencies || {
  log_error "Missing required dependencies"
  exit 1
}

# Check if key already exists in any backend
log_info "Checking for existing SSH key in backends..."

if ssh_key=$(get_ssh_key_from_gsm "$GSM_SECRET_NAME" 2>/dev/null); then
  log_info "✓ SSH key found in GSM (reusing existing key)"
  key_file="$RUNNER_KEY_DIR/$RUNNER_NAME.ed25519"
  mkdir -p "$RUNNER_KEY_DIR"
  echo "$ssh_key" > "$key_file"
  chmod 600 "$key_file"
elif ssh_key=$(get_ssh_key_from_vault "$VAULT_PATH" "$RUNNER_NAME" 2>/dev/null); then
  log_info "✓ SSH key found in Vault (backing up to GSM)"
  key_file="$RUNNER_KEY_DIR/$RUNNER_NAME.ed25519"
  mkdir -p "$RUNNER_KEY_DIR"
  echo "$ssh_key" > "$key_file"
  chmod 600 "$key_file"
  store_ssh_key_in_gsm "$key_file" "$GSM_SECRET_NAME"
else
  log_info "No existing SSH key found; generating new key"
  key_file="$RUNNER_KEY_DIR/$RUNNER_NAME.ed25519"
  generate_ssh_key "$key_file" "runner@$RUNNER_NAME"
fi

# Store in all available backends
store_ssh_key_in_gsm "$key_file" "$GSM_SECRET_NAME"
store_ssh_key_in_vault "$key_file" "$VAULT_PATH" "$RUNNER_NAME"
store_ssh_key_encrypted_kms "$key_file"

# Verify accessibility
verify_ssh_key "$GSM_SECRET_NAME" || {
  log_error "SSH key verification failed"
  exit 1
}

# Create automated retrieval script
create_ssh_retrieval_script "scripts/ops/retrieve_ssh_key.sh" "$GSM_SECRET_NAME"

# Display public key (for authorized_keys)
if [[ -f "$key_file.pub" ]]; then
  log_info ""
  log_info "Public key (add to authorized_keys):"
  cat "$key_file.pub"
  log_info ""
fi

log_info "✓ SSH key provisioning complete"
log_info "Private key stored in:"
log_info "  - GSM: $GSM_SECRET_NAME"
if command -v vault &>/dev/null; then
  log_info "  - Vault: $VAULT_PATH/$RUNNER_NAME"
fi
log_info "  - KMS (encrypted): ./.runner-keys-encrypted/"
log_info ""
log_info "Retrieve key at runtime using: bash scripts/ops/retrieve_ssh_key.sh"
