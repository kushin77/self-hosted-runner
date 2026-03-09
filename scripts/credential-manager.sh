#!/bin/bash
set -euo pipefail

##############################################################################
# Unified Credential Manager
# Purpose: Retrieve ephemeral credentials from GSM/Vault/KMS with auto-failover
# Usage: ./credential-manager.sh CREDENTIAL_NAME [retrieve_from]
#
# retrieve_from options: 'auto' (default), 'gsm', 'vault', 'kms'
##############################################################################

CREDENTIAL_NAME="${1:-}"
RETRIEVE_FROM="${2:-auto}"
CACHE_DIR="${CACHE_DIR:-.cache}"
AUDIT_LOG="${AUDIT_LOG:-./credential-access.log}"

# Configuration (via environment)
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
VAULT_ADDR="${VAULT_ADDR:-}"
AWS_KMS_KEY_ID="${AWS_KMS_KEY_ID:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1" >&2; }

audit_log() {
  local msg="$1"
  local timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "{\"timestamp\":\"$timestamp\",\"credential\":\"$CREDENTIAL_NAME\",\"source\":\"$2\",\"status\":\"$3\",\"msg\":\"$msg\"}" >> "$AUDIT_LOG"
}

##############################################################################
# LAYER 1: GCP Secret Manager (Primary)
##############################################################################

fetch_from_gsm() {
  if [ -z "$GCP_PROJECT_ID" ]; then
    log_warn "GCP_PROJECT_ID not configured, skipping GSM layer"
    audit_log "GSM layer not configured" "gsm" "skip"
    return 1
  fi

  log_info "Attempting GSM retrieval for $CREDENTIAL_NAME..."

  # Get OIDC token for GCP
  OIDC_TOKEN="" 
  if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    RESP=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=https://iamcredentials.googleapis.com" \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null || true)
    OIDC_TOKEN=$(echo "$RESP" | jq -r '.token // empty' 2>/dev/null || echo "")
  fi

  if [ -z "$OIDC_TOKEN" ]; then
    log_warn "OIDC token not available, trying ADC..."
    audit_log "OIDC fallback to ADC" "gsm" "attempt"
  fi

  # Retrieve secret from GSM
  CRED_VALUE=""
  for attempt in 1 2 3; do
    CRED_VALUE=$(gcloud secrets versions access latest --secret="$CREDENTIAL_NAME" \
      --project="$GCP_PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$CRED_VALUE" ]; then
      log_pass "GSM retrieval successful (attempt $attempt)"
      audit_log "GSM retrieval successful" "gsm" "success"
      SOURCE_LAYER="gsm"
      echo "$CRED_VALUE"
      return 0
    fi
    
    if [ $attempt -lt 3 ]; then
      sleep $((attempt * 2))
    fi
  done

  log_fail "GSM retrieval failed after 3 attempts"
  audit_log "GSM retrieval failed" "gsm" "failed"
  return 1
}

##############################################################################
# LAYER 2: HashiCorp Vault (Secondary)
##############################################################################

fetch_from_vault() {
  if [ -z "$VAULT_ADDR" ]; then
    log_warn "VAULT_ADDR not configured, skipping Vault layer"
    audit_log "Vault layer not configured" "vault" "skip"
    return 1
  fi

  log_info "Attempting Vault retrieval for $CREDENTIAL_NAME..."

  # Get JWT token for Vault auth
  JWT_TOKEN=""
  if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    RESP=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=$VAULT_ADDR" \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null || true)
    JWT_TOKEN=$(echo "$RESP" | jq -r '.token // empty' 2>/dev/null || echo "")
  fi

  if [ -z "$JWT_TOKEN" ]; then
    log_fail "JWT token not available for Vault auth"
    audit_log "JWT token unavailable" "vault" "failed"
    return 1
  fi

  # Authenticate to Vault
  AUTH_RESP=$(curl -sS "$VAULT_ADDR/v1/auth/jwt/login" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jwt\":\"$JWT_TOKEN\"}" 2>/dev/null || echo "")

  VAULT_TOKEN=$(echo "$AUTH_RESP" | jq -r '.auth.client_token // empty' 2>/dev/null || echo "")

  if [ -z "$VAULT_TOKEN" ]; then
    log_fail "Vault authentication failed"
    audit_log "Vault auth failed" "vault" "failed"
    return 1
  fi

  # Retrieve secret from Vault
  CRED_VALUE=""
  for attempt in 1 2 3; do
    SECRET_RESP=$(curl -sS "$VAULT_ADDR/v1/secret/data/credentials/$CREDENTIAL_NAME" \
      -H "X-Vault-Token: $VAULT_TOKEN" 2>/dev/null || echo "")

    CRED_VALUE=$(echo "$SECRET_RESP" | jq -r '.data.data.value // empty' 2>/dev/null || echo "")

    if [ -n "$CRED_VALUE" ]; then
      log_pass "Vault retrieval successful (attempt $attempt)"
      audit_log "Vault retrieval successful" "vault" "success"
      SOURCE_LAYER="vault"
      
      # Revoke token to maintain ephemeral nature
      curl -sS "$VAULT_ADDR/v1/auth/token/revoke-self" \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" >/dev/null 2>&1 || true
      
      echo "$CRED_VALUE"
      return 0
    fi

    if [ $attempt -lt 3 ]; then
      sleep $((attempt * 2))
    fi
  done

  log_fail "Vault retrieval failed after 3 attempts"
  audit_log "Vault retrieval failed" "vault" "failed"
  return 1
}

##############################################################################
# LAYER 3: AWS KMS (Tertiary)
##############################################################################

fetch_from_kms() {
  if [ -z "$AWS_KMS_KEY_ID" ]; then
    log_warn "AWS_KMS_KEY_ID not configured, skipping KMS layer"
    audit_log "KMS layer not configured" "kms" "skip"
    return 1
  fi

  log_info "Attempting KMS retrieval for $CREDENTIAL_NAME..."

  # Get AWS credentials via OIDC
  if [[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    OIDC_TOKEN=$(curl -sS "${ACTIONS_ID_TOKEN_REQUEST_URL}?audience=https://sts.amazonaws.com" \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" 2>/dev/null || true | jq -r '.token // empty')
  fi

  # Try to get AWS caller identity (validates auth)
  CALLER_ID=$(aws sts get-caller-identity --output json 2>/dev/null | jq -r '.Account // empty' || echo "")

  if [ -z "$CALLER_ID" ]; then
    log_fail "AWS authentication failed"
    audit_log "AWS auth failed" "kms" "failed"
    return 1
  fi

  # Retrieve wrapped credential from Secrets Manager, decrypt with KMS
  CRED_VALUE=""
  for attempt in 1 2 3; do
    # Get wrapped credential from AWS Secrets Manager
    SECRET_JSON=$(aws secretsmanager get-secret-value \
      --secret-id "$CREDENTIAL_NAME" \
      --query SecretString \
      --output text 2>/dev/null || echo "")

    if [ -n "$SECRET_JSON" ]; then
      # Extract the wrapped ciphertext and decrypt
      CIPHERTEXT=$(echo "$SECRET_JSON" | jq -r '.ciphertext // empty' 2>/dev/null || echo "")

      if [ -n "$CIPHERTEXT" ]; then
        PLAINTEXT=$(aws kms decrypt \
          --ciphertext-blob "fileb://<(echo $CIPHERTEXT | base64 -d)" \
          --key-id "$AWS_KMS_KEY_ID" \
          --query Plaintext \
          --output text 2>/dev/null | base64 -d)

        CRED_VALUE="$PLAINTEXT"
      else
        # If no wrapping, return the secret directly
        CRED_VALUE="$SECRET_JSON"
      fi

      if [ -n "$CRED_VALUE" ]; then
        log_pass "KMS retrieval successful (attempt $attempt)"
        audit_log "KMS retrieval successful" "kms" "success"
        SOURCE_LAYER="kms"
        echo "$CRED_VALUE"
        return 0
      fi
    fi

    if [ $attempt -lt 3 ]; then
      sleep $((attempt * 2))
    fi
  done

  log_fail "KMS retrieval failed after 3 attempts"
  audit_log "KMS retrieval failed" "kms" "failed"
  return 1
}

##############################################################################
# FAILOVER ORCHESTRATION
##############################################################################

retrieve_with_failover() {
  case "$RETRIEVE_FROM" in
    "gsm")
      fetch_from_gsm && return 0
      ;;
    "vault")
      fetch_from_vault && return 0
      ;;
    "kms")
      fetch_from_kms && return 0
      ;;
    "auto")
      # Try in order: GSM → Vault → KMS
      fetch_from_gsm && return 0
      log_warn "GSM failed, attempting Vault..."
      fetch_from_vault && return 0
      log_warn "Vault failed, attempting KMS..."
      fetch_from_kms && return 0
      ;;
    *)
      log_fail "Invalid retrieve_from option: $RETRIEVE_FROM"
      return 1
      ;;
  esac

  # All layers failed
  log_fail "All credential layers failed for $CREDENTIAL_NAME"
  audit_log "All layers failed" "all" "failed"
  return 1
}

##############################################################################
# MAIN
##############################################################################

if [ -z "$CREDENTIAL_NAME" ]; then
  log_fail "Usage: $0 CREDENTIAL_NAME [retrieve_from]"
  log_fail "  retrieve_from: 'auto' (default), 'gsm', 'vault', 'kms'"
  exit 1
fi

mkdir -p "$CACHE_DIR"

log_info "Retrieving credential: $CREDENTIAL_NAME (from: $RETRIEVE_FROM)"

CREDENTIAL_VALUE=$(retrieve_with_failover) || {
  audit_log "Credential retrieval failed" "all" "error"
  exit 1
}

# Prepare structured JSON output (emit only JSON on stdout). Keep human logs on stderr.
# Generate an audit id
if command -v uuidgen >/dev/null 2>&1; then
  AUDIT_ID=$(uuidgen)
else
  AUDIT_ID=$(python3 - <<'PY'
import uuid
print(uuid.uuid4().hex)
PY
)
fi

# Emit JSON with proper escaping using python3
export CREDENTIAL_VALUE
export SOURCE_LAYER
export AUDIT_ID
python3 - <<'PY'
import json,os,sys
cred=os.environ.get('CREDENTIAL_VALUE','')
out={
  'credential': cred,
  'source': os.environ.get('SOURCE_LAYER',''),
  'cached': False,
  'expires_at': '',
  'audit_id': os.environ.get('AUDIT_ID','')
}
sys.stdout.write(json.dumps(out))
PY

log_pass "Credential retrieved successfully"
exit 0
