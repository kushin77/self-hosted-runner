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
  scripts/cred-helpers/fetch-from-gsm-real.sh "$CREDENTIAL_NAME"
}

##############################################################################
# LAYER 2: HashiCorp Vault (Secondary)
##############################################################################

fetch_from_vault() {
  scripts/cred-helpers/fetch-from-vault-real.sh "$CREDENTIAL_NAME"
}

##############################################################################
# LAYER 3: AWS KMS (Tertiary)
##############################################################################

fetch_from_kms() {
  scripts/cred-helpers/fetch-from-kms-real.sh "$CREDENTIAL_NAME"
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
