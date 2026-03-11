#!/usr/bin/env bash
set -euo pipefail

# Encrypts sensitive mirrored credentials using GCP KMS
# Stores ciphertexts as audit trail (ephemeral with auto-cleanup)

PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
REGION="${KMS_REGION:-us-central1}"
KEYRING_NAME="nexusshield"
KEY_NAME="mirror-key"
AUDIT_DIR="${AUDIT_DIR:-./.mirror-audit}"

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

check_kms_key() {
  if ! gcloud kms keys describe "$KEY_NAME" \
    --location="$REGION" \
    --keyring="$KEYRING_NAME" \
    --project="$PROJECT_ID" &>/dev/null 2>&1; then
    log_error "KMS key not found: $KEYRING_NAME/$KEY_NAME"
    log_error "Run: bash scripts/security/provision_kms_key.sh --grant-perms"
    return 1
  fi
}

encrypt_file() {
  local input_file="$1"
  
  if [[ ! -f "$input_file" ]]; then
    log_error "File not found: $input_file"
    return 1
  fi
  
  mkdir -p "$AUDIT_DIR"
  local timestamp=$(date -u +%Y%m%d_%H%M%S)
  local file_name=$(basename "$input_file")
  local output_file="$AUDIT_DIR/${file_name}.enc.$timestamp"
  
  log_info "Encrypting $input_file → $output_file"
  
  gcloud kms encrypt \
    --keyring="$KEYRING_NAME" \
    --key="$KEY_NAME" \
    --location="$REGION" \
    --plaintext-file="$input_file" \
    --ciphertext-file="$output_file" \
    --project="$PROJECT_ID" || {
    log_error "Failed to encrypt: $input_file"
    return 1
  }
  
  log_info "✓ Encrypted ciphertext: $output_file"
  echo "$output_file"
}

decrypt_file() {
  local encrypted_file="$1"
  
  if [[ ! -f "$encrypted_file" ]]; then
    log_error "Encrypted file not found: $encrypted_file"
    return 1
  fi
  
  local plaintext_file="${encrypted_file%.enc.*}"
  
  log_info "Decrypting $encrypted_file → $plaintext_file"
  
  gcloud kms decrypt \
    --keyring="$KEYRING_NAME" \
    --key="$KEY_NAME" \
    --location="$REGION" \
    --ciphertext-file="$encrypted_file" \
    --plaintext-file="$plaintext_file" \
    --project="$PROJECT_ID" || {
    log_error "Failed to decrypt: $encrypted_file"
    return 1
  }
  
  log_info "✓ Decrypted plaintext: $plaintext_file"
  echo "$plaintext_file"
}

encrypt_string() {
  local plaintext="$1"
  local temp_file=$(mktemp)
  trap "rm -f $temp_file" return
  
  echo -n "$plaintext" > "$temp_file"
  
  gcloud kms encrypt \
    --keyring="$KEYRING_NAME" \
    --key="$KEY_NAME" \
    --location="$REGION" \
    --plaintext-file="$temp_file" \
    --ciphertext-file=- \
    --project="$PROJECT_ID" 2>/dev/null | base64 -w0
}

decrypt_string() {
  local ciphertext_base64="$1"
  
  echo "$ciphertext_base64" | base64 -d | gcloud kms decrypt \
    --keyring="$KEYRING_NAME" \
    --key="$KEY_NAME" \
    --location="$REGION" \
    --ciphertext-file=- \
    --plaintext-file=- \
    --project="$PROJECT_ID" 2>/dev/null
}

cleanup_audit() {
  local max_age_days="${1:-7}"
  
  log_info "Cleaning up audit files older than $max_age_days days"
  
  if [[ -d "$AUDIT_DIR" ]]; then
    find "$AUDIT_DIR" -name "*.enc.*" -mtime +"$max_age_days" -delete || true
    log_info "✓ Cleanup complete"
  fi
}

# Parse command
if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  encrypt-file <path>           Encrypt a file and save ciphertext
  decrypt-file <ciphertext-path> Decrypt a ciphertext file
  encrypt-string <plaintext>    Encrypt a string (outputs base64)
  decrypt-string <base64>       Decrypt a base64-encoded string
  cleanup [days]                Remove audit files older than N days (default: 7)

Examples:
  # Encrypt a migration artifact
  \$ bash $0 encrypt-file ./mirror-output.json

  # Decrypt and review
  \$ bash $0 decrypt-file ./.mirror-audit/mirror-output.json.enc.20260311_160000

  # Encrypt a credential value
  \$ bash $0 encrypt-string "my-secret-value"

  # Clean old audit files
  \$ bash $0 cleanup 7
EOF
  exit 1
fi

check_kms_key

command="$1"
shift

case "$command" in
  encrypt-file)
    encrypt_file "$1"
    ;;
  decrypt-file)
    decrypt_file "$1"
    ;;
  encrypt-string)
    encrypt_string "$1"
    ;;
  decrypt-string)
    decrypt_string "$1"
    ;;
  cleanup)
    cleanup_audit "${1:-7}"
    ;;
  *)
    log_error "Unknown command: $command"
    exit 1
    ;;
esac
