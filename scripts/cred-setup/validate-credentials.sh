#!/usr/bin/env bash
set -euo pipefail

# validate-credentials.sh
# Validate presence and basic connectivity for GSM, Vault, and AWS (non-destructive).

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../audit"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/validate-credentials-${TIMESTAMP}.log"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG_FILE"; }

log "Starting credential validation"

# Check required env vars (not logging their values)
missing=()

check_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  else
    log "Found env var: $name"
  fi
}

# List of env vars typically required (optional depending on provider)
env_vars=(
  GCP_WORKLOAD_IDENTITY_PROVIDER
  GCP_SERVICE_ACCOUNT
  VAULT_ADDR
  VAULT_ROLE_ID
  VAULT_SECRET_ID
  VAULT_TOKEN
  AWS_ROLE_TO_ASSUME
  AWS_REGION
)

for v in "${env_vars[@]}"; do
  check_env "$v"
done

if [ ${#missing[@]} -gt 0 ]; then
  log "MISSING environment variables: ${missing[*]}"
  log "Please add at least one provider's credentials to proceed as described in docs/ADD_CREDENTIAL_PROVIDER.md"
  exit 2
fi

# GSM quick check (if gcloud available and workload provider + service account present)
if command -v gcloud >/dev/null 2>&1; then
  log "gcloud present: running lightweight GSM check (non-destructive)"
  # Try to list secrets (may fail if not authenticated) — do not output secrets
  if gcloud secrets list --project="${GCP_PROJECT_ID:-}" >/dev/null 2>&1; then
    log "GSM: secrets.list succeeded"
  else
    log "GSM: secrets.list failed (ok if using OIDC on GitHub Actions; will validate in runner)"
  fi
else
  log "gcloud not installed; skip GSM runtime check"
fi

# Vault check (if VAULT_ADDR provided)
if [ -n "${VAULT_ADDR:-}" ]; then
  if command -v vault >/dev/null 2>&1; then
    log "Vault CLI present: checking Vault status"
    if vault status >/dev/null 2>&1; then
      log "Vault status: OK"
    else
      log "Vault status: Unreachable or unauthenticated"
    fi
  else
    log "Vault CLI not installed; skip Vault runtime check"
  fi
fi

# AWS check — validate AWS_REGION and role variable
if [ -n "${AWS_ROLE_TO_ASSUME:-}" ]; then
  if command -v aws >/dev/null 2>&1; then
    log "AWS CLI present: running sts get-caller-identity (will not assume role)"
    if aws sts get-caller-identity >/dev/null 2>&1; then
      log "AWS: caller identity exists"
    else
      log "AWS: caller identity check failed (ok if using OIDC in workflow)"
    fi
  else
    log "AWS CLI not installed; skip AWS runtime check"
  fi
fi

log "Validation complete. Review $LOG_FILE for details."

# Emit a short machine-readable summary
summary_file="$LOG_DIR/validate-credentials-summary-${TIMESTAMP}.json"
cat > "$summary_file" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "missing_env": ${#missing[@]},
  "missing_list": [$(printf '"%s",' "${missing[@]}" | sed 's/,$//')]
}
EOF

log "Summary: $summary_file"

exit 0
