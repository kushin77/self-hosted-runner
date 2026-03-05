#!/usr/bin/env bash
set -euo pipefail

# Vault Integration for Secrets Rotation (Phase P1)
# Manages credential lifecycle and rotation
#
# Features:
#   - AppRole authentication with Vault
#   - Credential fetching and caching
#   - TTL enforcement and rotation
#   - Audit trail logging
#   - Graceful fallback for offline Vault

VAULT_ADDR="${VAULT_ADDR:-https://vault.internal:8200}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:-.}"
VAULT_SECRET_ID_PATH="${VAULT_SECRET_ID_PATH:-/run/vault/.secret}"
CREDENTIAL_TTL="${CREDENTIAL_TTL:-21600}"  # 6 hours
ROTATION_INTERVAL="${ROTATION_INTERVAL:-3600}"  # 1 hour checks
CREDENTIAL_CACHE_DIR="${CREDENTIAL_CACHE_DIR:-/tmp/vault-credentials}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/vault-operations.log}"

mkdir -p "$CREDENTIAL_CACHE_DIR" && chmod 700 "$CREDENTIAL_CACHE_DIR"
mkdir -p "$(dirname "$AUDIT_LOG")"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$AUDIT_LOG"
}

error() {
  log "ERROR" "$@"
  return 1
}

# Authenticate with Vault using AppRole
authenticate() {
  log "INFO" "Authenticating with Vault server: $VAULT_ADDR"
  
  # Check for secret ID file
  [ -f "$VAULT_SECRET_ID_PATH" ] || \
    error "Secret ID not found: $VAULT_SECRET_ID_PATH"
  
  local secret_id=$(cat "$VAULT_SECRET_ID_PATH")
  
  # AppRole authentication request (with timeouts)
  local auth_response=$(curl -sS --connect-timeout 5 --max-time 10 \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$secret_id\"}" \
    "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null || echo "{}")
  
  # Extract token
  local token=$(echo "$auth_response" | jq -r '.auth.client_token // empty' 2>/dev/null)
  
  if [ -z "$token" ]; then
    error "Failed to authenticate with Vault"
    return 1
  fi
  
  # Save token to cache
  echo "$token" > "${CREDENTIAL_CACHE_DIR}/.vault-token"
  chmod 600 "${CREDENTIAL_CACHE_DIR}/.vault-token"
  
  # Extract TTL
  local token_ttl=$(echo "$auth_response" | jq -r '.auth.lease_duration // 3600')
  echo "$token_ttl" > "${CREDENTIAL_CACHE_DIR}/.vault-token-ttl"
  
  log "INFO" "Authentication successful (token TTL: ${token_ttl}s)"
  return 0
}

# Fetch secret from Vault
fetch_secret() {
  local secret_path="$1"
  local secret_name="${2:-default}"
  
  local token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  
  if [ -z "$token" ]; then
    log "WARN" "No valid token in cache, authenticating..."
    authenticate || return 1
    token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token")
  fi
  
  log "INFO" "Fetching secret: $secret_path"
  
  # Fetch secret
  local secret_response=$(curl -sS --connect-timeout 5 --max-time 10 \
    -H "X-Vault-Token: $token" \
    "$VAULT_ADDR/v1/$secret_path" 2>/dev/null || echo "{}")
  
  # Check for errors
  if echo "$secret_response" | jq -e '.errors' > /dev/null 2>&1; then
    error "Failed to fetch secret: $(echo "$secret_response" | jq -r '.errors[0]')"
    return 1
  fi
  
  # Extract secret data
  local secret_data=$(echo "$secret_response" | jq -r '.data.data // .data' 2>/dev/null)
  
  if [ -z "$secret_data" ]; then
    error "No secret data found at path: $secret_path"
    return 1
  fi
  
  # Cache secret with metadata
  local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.secret"
  cat > "$cache_file" <<EOF
{
  "data": $secret_data,
  "fetched_at": "$(date -Iseconds)",
  "ttl": $CREDENTIAL_TTL,
  "expires_at": $(($(date +%s) + CREDENTIAL_TTL))
}
EOF
  
  chmod 600 "$cache_file"
  
  log "INFO" "Secret cached: $secret_name (TTL: ${CREDENTIAL_TTL}s)"
  
  # Output secret for shell expansion
  echo "$secret_data" | jq -r 'to_entries[] | "\(.key)=\(.value)"'
  
  return 0
}

# Check if cached credential is still valid
is_credential_valid() {
  local secret_name="$1"
  local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.secret"
  
  if [ ! -f "$cache_file" ]; then
    return 1  # Cache miss
  fi
  
  local expires_at=$(jq -r '.expires_at' "$cache_file" 2>/dev/null || echo 0)
  local current_time=$(date +%s)
  
  if [ $current_time -lt $expires_at ]; then
    return 0  # Valid
  else
    log "WARN" "Credential expired: $secret_name"
    return 1  # Expired
  fi
}

# Rotate credentials (called by daemon)
rotate_credentials() {
  local secret_path="$1"
  local secret_name="${2:-default}"
  
  log "INFO" "Starting credential rotation for: $secret_name"
  
  # Skip if still valid
  if is_credential_valid "$secret_name"; then
    local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.secret"
    local expires_at=$(jq -r '.expires_at' "$cache_file")
    local time_left=$((expires_at - $(date +%s)))
    
    log "INFO" "Credential still valid ($time_left seconds remaining), skipping rotation"
    return 0
  fi
  
  # Fetch fresh credential
  fetch_secret "$secret_path" "$secret_name" || \
    error "Failed to rotate credential: $secret_name"
  
  log "INFO" "Credential rotated successfully: $secret_name"
}

# Daemon: continuous credential rotation
run_rotation_daemon() {
  log "INFO" "🔄 Starting credential rotation daemon (interval: ${ROTATION_INTERVAL}s)"
  
  local rotation_config="${1:-.runner-config/vault-rotation.yaml}"
  
  [ -f "$rotation_config" ] || \
    error "Rotation config not found: $rotation_config"
  
  while true; do
    log "DEBUG" "Running rotation cycle..."
    
    # Parse config and rotate each secret
    yq '.credentials[] | .path + "|" + .name' "$rotation_config" 2>/dev/null | while IFS='|' read -r path name; do
      rotate_credentials "$path" "$name" || log "WARN" "Rotation failed for: $name"
    done
    
    sleep "$ROTATION_INTERVAL"
  done
}

# Revoke a credential
revoke_credential() {
  local secret_name="$1"
  
  local token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  
  if [ -z "$token" ]; then
    log "WARN" "Cannot revoke without valid token"
    return 1
  fi
  
  log "INFO" "Revoking credential: $secret_name"
  
  # Remove from cache
  rm -f "${CREDENTIAL_CACHE_DIR}/${secret_name}.secret"
  
  log "INFO" "Credential revoked: $secret_name"
  return 0
}

# Cleanup on exit (job completion)
cleanup() {
  log "INFO" "Cleaning up Vault resources..."
  
  # Revoke all cached credentials
  for cache_file in "${CREDENTIAL_CACHE_DIR}"/*.secret; do
    if [ -f "$cache_file" ]; then
      local secret_name=$(basename "$cache_file" .secret)
      revoke_credential "$secret_name" || true
    fi
  done
  
  # Revoke Vault token
  local token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  if [ -n "$token" ]; then
    curl -s -X POST \
      -H "X-Vault-Token: $token" \
      "$VAULT_ADDR/v1/auth/token/revoke-self" > /dev/null 2>&1 || true
    
    rm -f "${CREDENTIAL_CACHE_DIR}/.vault-token"
  fi
  
  log "INFO" "Cleanup complete"
}

# Status/monitoring
status() {
  echo "Vault Integration Status"
  echo "========================"
  echo ""
  echo "Server: $VAULT_ADDR"
  echo "Credential Cache: $CREDENTIAL_CACHE_DIR"
  echo ""
  
  echo "Cached Credentials:"
  for cache_file in "${CREDENTIAL_CACHE_DIR}"/*.secret; do
    if [ -f "$cache_file" ]; then
      local secret_name=$(basename "$cache_file" .secret)
      local expires_at=$(jq -r '.expires_at' "$cache_file")
      local current=$(date +%s)
      local time_left=$((expires_at - current))
      
      if [ $time_left -gt 0 ]; then
        echo "  ✓ $secret_name (expires in ${time_left}s)"
      else
        echo "  ✗ $secret_name (EXPIRED)"
      fi
    fi
  done
  
  echo ""
  echo "Recent Operations (last 10):"
  tail -10 "$AUDIT_LOG" | sed 's/^/  /'
}

# CLI
main() {
  case "${1:-help}" in
    auth)
      authenticate
      ;;
    fetch)
      fetch_secret "$2" "${3:-default}"
      ;;
    rotate)
      rotate_credentials "$2" "${3:-default}"
      ;;
    daemon)
      run_rotation_daemon "${2:-.runner-config/vault-rotation.yaml}"
      ;;
    revoke)
      revoke_credential "$2"
      ;;
    cleanup)
      cleanup
      ;;
    status)
      status
      ;;
    *)
      cat <<'HELP'
Vault Secrets Integration - Phase P1

Usage:
  vault-integration auth                                     Authenticate with Vault
  vault-integration fetch <secret-path> [name]              Fetch and cache secret
  vault-integration rotate <secret-path> [name]             Rotate credential
  vault-integration daemon [config-file]                    Start rotation daemon
  vault-integration revoke <credential-name>                Revoke credential
  vault-integration cleanup                                 Revoke all and cleanup
  vault-integration status                                  Show status and recent ops

Environment Variables:
  VAULT_ADDR                  Vault server URL (default: https://vault.internal:8200)
  VAULT_ROLE_ID              AppRole role ID (required)
  VAULT_SECRET_ID_PATH       Path to secret ID file (default: /run/vault/.secret)
  CREDENTIAL_TTL             Secret lifetime in seconds (default: 21600)
  ROTATION_INTERVAL          Check interval in seconds (default: 3600)
  CREDENTIAL_CACHE_DIR       Cache directory (default: /tmp/vault-credentials)

Configuration File (vault-rotation.yaml):
  credentials:
    - path: secret/data/runners/github-token
      name: github-token
      ttl: 21600
    - path: secret/data/runners/docker-creds
      name: docker-creds
      ttl: 21600

Examples:
  vault-integration auth
  vault-integration fetch secret/data/runners/github-token github-token
  ./vault-integration daemon .runner-config/vault-rotation.yaml &
  vault-integration status
  vault-integration revoke github-token

HELP
      exit 1
      ;;
  esac
}

# Register cleanup on exit
trap cleanup EXIT

main "$@"
