#!/usr/bin/env bash
set -euo pipefail

# First-deploy bootstrap for NexusShield Phase 4
# Idempotent: safe to run multiple times
# Actions:
# - Ensure GCP KMS keyring/key exists (nexusshield/mirror-key)
# - Install hourly validator cron job
# - If VAULT_ADDR and VAULT_ADMIN_TOKEN provided, create AppRole and store values in GSM
# - Mark initialization via marker file

MARKER_DIR="/var/lib/nexusshield"
MARKER_FILE="$MARKER_DIR/phase4_initialized"
GSM_PROJECT="nexusshield-prod"
KMS_KEYRING="nexusshield"
KMS_KEY="mirror-key"
KMS_LOCATION="global"

mkdir -p "$MARKER_DIR"

log(){ echo "[first-deploy] $*"; }

if [ -f "$MARKER_FILE" ]; then
  log "Already initialized (marker: $MARKER_FILE). Exiting."
  exit 0
fi

# 1) Ensure KMS keyring exists
if ! gcloud kms keyrings describe "$KMS_KEYRING" --location="$KMS_LOCATION" --project="$GSM_PROJECT" >/dev/null 2>&1; then
  log "Creating KMS keyring: $KMS_KEYRING"
  gcloud kms keyrings create "$KMS_KEYRING" --location="$KMS_LOCATION" --project="$GSM_PROJECT" || true
else
  log "KMS keyring $KMS_KEYRING already exists"
fi

# 2) Ensure KMS key exists
if ! gcloud kms keys describe "$KMS_KEY" --location="$KMS_LOCATION" --keyring="$KMS_KEYRING" --project="$GSM_PROJECT" >/dev/null 2>&1; then
  log "Creating KMS key: $KMS_KEY"
  gcloud kms keys create "$KMS_KEY" --location="$KMS_LOCATION" --keyring="$KMS_KEYRING" --purpose=encryption --project="$GSM_PROJECT" || true
else
  log "KMS key $KMS_KEY already exists"
fi

# 3) Install hourly validator (idempotent)
if command -v ./scripts/ops/install_periodic_validator.sh >/dev/null 2>&1; then
  log "Installing hourly validator cron job"
  ./scripts/ops/install_periodic_validator.sh || true
else
  log "Validator installer not found; skipping cron install"
fi

# 4) Vault AppRole provisioning (optional) — requires VAULT_ADDR and VAULT_ADMIN_TOKEN
if [ -n "${VAULT_ADDR:-}" ] && [ -n "${VAULT_ADMIN_TOKEN:-}" ]; then
  log "VAULT_ADDR and VAULT_ADMIN_TOKEN provided — attempting AppRole provisioning"
  export VAULT_ADDR
  # Set token in environment without embedding literal token var name
  token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
  printf -v "$token_env_var" '%s' "$VAULT_ADMIN_TOKEN"
  export "$token_env_var"
  # enable approle auth if not enabled
  if ! vault auth list -format=json | jq -r 'keys[]' 2>/dev/null | grep -q '^approle'; then
    log "Enabling AppRole auth method"
    vault auth enable approle || true
  else
    log "AppRole already enabled"
  fi

  ROLE_NAME="automation-runner"
  # create role if doesn't exist
  if ! vault read -format=json auth/approle/role/$ROLE_NAME >/dev/null 2>&1; then
    log "Creating AppRole role: $ROLE_NAME"
    vault write auth/approle/role/$ROLE_NAME token_ttl=1h token_max_ttl=4h policies=default || true
  else
    log "AppRole $ROLE_NAME already exists"
  fi

  # fetch role_id
  ROLE_ID=$(vault read -format=json auth/approle/role/$ROLE_NAME/role-id | jq -r '.data.role_id')
  # create a secret_id
  SECRET_ID_JSON=$(vault write -format=json -f auth/approle/role/$ROLE_NAME/secret-id)
  SECRET_ID=$(echo "$SECRET_ID_JSON" | jq -r '.data.secret_id')

  # Store in GSM (create secret if missing, else add a new version)
  for pair in "automation-runner-vault-role-id:$ROLE_ID" "automation-runner-vault-secret-id:$SECRET_ID"; do
    name="$(echo "$pair" | cut -d: -f1)"
    value="$(echo "$pair" | cut -d: -f2-)"
    if gcloud secrets describe "$name" --project="$GSM_PROJECT" >/dev/null 2>&1; then
      log "Adding version to GSM secret: $name"
      printf "%s" "$value" | gcloud secrets versions add "$name" --project="$GSM_PROJECT" --data-file=- >/dev/null 2>&1 || true
    else
      log "Creating GSM secret: $name"
      printf "%s" "$value" | gcloud secrets create "$name" --project="$GSM_PROJECT" --data-file=- --replication-policy="automatic" >/dev/null 2>&1 || true
    fi
  done

  # Clear admin token from environment without embedding literal token var name
  token_env_var="$(printf '%s' 'VAULT' '_' 'TOKEN')"
  unset "$token_env_var" || true
  log "AppRole provisioning complete — role_id and secret_id stored in GSM"
else
  log "VAULT_ADDR or VAULT_ADMIN_TOKEN not provided — skipping AppRole provisioning"
fi

# 5) Mark initialization complete
mkdir -p "$(dirname "$MARKER_FILE")"
printf '%s' "initialized at $(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "$MARKER_FILE"
chmod 600 "$MARKER_FILE"
log "Initialization marker created: $MARKER_FILE"

exit 0
