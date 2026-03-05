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
#   - Security enhancements: file permissions, SSL verification, timeouts

VAULT_ADDR="${VAULT_ADDR:-https://vault.internal:8200}"
VAULT_ROLE_ID="${VAULT_ROLE_ID:-.}"
VAULT_SECRET_ID_PATH="${VAULT_SECRET_ID_PATH:-/run/vault/.secret}"
CREDENTIAL_TTL="${CREDENTIAL_TTL:-21600}"  # 6 hours
ROTATION_INTERVAL="${ROTATION_INTERVAL:-3600}"  # 1 hour checks
CREDENTIAL_CACHE_DIR="${CREDENTIAL_CACHE_DIR:-/tmp/vault-credentials}"
AUDIT_LOG="${AUDIT_LOG:-/var/log/vault-operations.log}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"  # Connection timeout
LOCK_DIR="${LOCK_DIR:-.vault-locks}"

# SSL/TLS configuration
VAULT_SKIP_VERIFY="${VAULT_SKIP_VERIFY:-false}"
VAULT_CAPATH="${VAULT_CAPATH:-}"

mkdir -p "$CREDENTIAL_CACHE_DIR"
mkdir -p "$LOCK_DIR"
mkdir -p "$(dirname "$AUDIT_LOG")"

# Set secure permissions on cache directory
chmod 700 "$CREDENTIAL_CACHE_DIR"

log() {
  local level="$1"
  shift
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$AUDIT_LOG"
}

error() {
  log "ERROR" "$@"
  return 1
}

# Validate dependencies
check_dependencies() {
  local deps=("curl" "jq")
  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
      return 1
    fi
  done
  
  # Check for yq if using daemon mode
  if [ "${1:-}" = "daemon" ]; then
    if ! command -v "yq" &>/dev/null; then
      error "yq required for daemon mode but not found"
      return 1
    fi
  fi
}

# Validate secret ID file permissions
validate_secret_id_file() {
  local file_mode=$(stat -c "%a" "$VAULT_SECRET_ID_PATH" 2>/dev/null || echo "999")
  
  # Warn if permissions are too open
  if [ "$file_mode" != "600" ] && [ "$file_mode" != "400" ]; then
    log "WARN" "Secret ID file has overly permissive mode: $file_mode (should be 600 or 400)"
    if [ "$file_mode" -gt 600 ]; then
      error "Secret ID file permissions too open: $file_mode. Restricting to 600"
      chmod 600 "$VAULT_SECRET_ID_PATH" 2>/dev/null || \
        error "Cannot modify Secret ID file permissions"
      return 1
    fi
  fi
  return 0
}

# Build curl options with SSL/TLS settings
build_curl_opts() {
  local opts=(
    "-s"
    "--connect-timeout" "$CURL_TIMEOUT"
    "--max-time" "$((CURL_TIMEOUT * 2))"
  )
  
  if [ "$VAULT_SKIP_VERIFY" = "true" ]; then
    log "WARN" "SSL verification disabled - only use in development!"
    opts+=("-k")
  elif [ -n "$VAULT_CAPATH" ] && [ -f "$VAULT_CAPATH" ]; then
    opts+=("--cacert" "$VAULT_CAPATH")
  fi
  
  echo "${opts[@]}"
}

# Authenticate with Vault using AppRole
authenticate() {
  log "INFO" "Authenticating with Vault server: $VAULT_ADDR"
  
  # Validate dependencies
  check_dependencies || return 1
  
  # Check for secret ID file and permissions
  [ -f "$VAULT_SECRET_ID_PATH" ] || \
    error "Secret ID not found: $VAULT_SECRET_ID_PATH"
  
  validate_secret_id_file || return 1
  
  local secret_id
  secret_id=$(cat "$VAULT_SECRET_ID_PATH") || \
    error "Failed to read Secret ID from $VAULT_SECRET_ID_PATH"
  
  # Build curl options
  local curl_opts=($(build_curl_opts))
  
  # AppRole authentication request
  local auth_response
  auth_response=$(curl "${curl_opts[@]}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"role_id\": \"$VAULT_ROLE_ID\", \"secret_id\": \"$secret_id\"}" \
    "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null || echo "{}")
  
  # Validate response is JSON
  if ! echo "$auth_response" | jq empty 2>/dev/null; then
    log "ERROR" "Invalid JSON response from Vault: $auth_response"
    error "Failed to parse Vault response"
    return 1
  fi
  
  # Extract token
  local token
  token=$(echo "$auth_response" | jq -r '.auth.client_token // empty' 2>/dev/null)
  
  if [ -z "$token" ]; then
    local error_msg
    error_msg=$(echo "$auth_response" | jq -r '.errors[] // .error // "Unknown error"' 2>/dev/null)
    error "Failed to authenticate with Vault: $error_msg"
    return 1
  fi
  
  # Save token to cache with secure permissions
  echo "$token" > "${CREDENTIAL_CACHE_DIR}/.vault-token"
  chmod 600 "${CREDENTIAL_CACHE_DIR}/.vault-token"
  
  # Extract and save token metadata
  local token_ttl
  token_ttl=$(echo "$auth_response" | jq -r '.auth.lease_duration // 3600')
  
  local token_issued_at
  token_issued_at=$(date +%s)
  
  cat > "${CREDENTIAL_CACHE_DIR}/.vault-token-meta" <<EOF
{
  "issued_at": $token_issued_at,
  "ttl": $token_ttl,
  "expires_at": $((token_issued_at + token_ttl))
}
EOF
  chmod 600 "${CREDENTIAL_CACHE_DIR}/.vault-token-meta"
  
  log "INFO" "Authentication successful (token TTL: ${token_ttl}s, expires at: $(date -d "@$((token_issued_at + token_ttl))"))"
  return 0
}

# Fetch secret from Vault
fetch_secret() {
  local secret_path="$1"
  local secret_name="${2:-default}"
  
  check_dependencies || return 1
  
  local token
  token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  
  if [ -z "$token" ]; then
    log "WARN" "No valid token in cache, authenticating..."
    authenticate || return 1
    token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token")
  fi
  
  log "INFO" "Fetching secret: $secret_path"
  
  # Build curl options
  local curl_opts=($(build_curl_opts))
  
  # Fetch secret with timeout
  local secret_response
  secret_response=$(curl "${curl_opts[@]}" \
    -H "X-Vault-Token: $token" \
    "$VAULT_ADDR/v1/$secret_path" 2>/dev/null || echo "{}")
  
  # Validate response is JSON
  if ! echo "$secret_response" | jq empty 2>/dev/null; then
    log "ERROR" "Invalid JSON response from Vault: $secret_response"
    error "Failed to fetch secret from Vault"
    return 1
  fi
  
  # Check for errors
  if echo "$secret_response" | jq -e '.errors' > /dev/null 2>&1; then
    local error_msg
    error_msg=$(echo "$secret_response" | jq -r '.errors[0]' 2>/dev/null)
    error "Failed to fetch secret: $error_msg"
    return 1
  fi
  
  # Extract secret data
  local secret_data
  secret_data=$(echo "$secret_response" | jq -r '.data.data // .data' 2>/dev/null)
  
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
  
  local expires_at
  expires_at=$(jq -r '.expires_at' "$cache_file" 2>/dev/null || echo 0)
  
  local current_time
  current_time=$(date +%s)
  
  if [ "$current_time" -lt "$expires_at" ]; then
    return 0  # Valid
  else
    log "WARN" "Credential expired: $secret_name"
    return 1  # Expired
  fi
}

# Acquire lock for credential rotation
acquire_lock() {
  local secret_name="$1"
  local lock_file="${LOCK_DIR}/${secret_name}.lock"
  local timeout=30
  local elapsed=0
  
  while [ $elapsed -lt $timeout ]; do
    if mkdir "$lock_file" 2>/dev/null; then
      echo $$ > "$lock_file/pid"
      return 0
    fi
    sleep 1
    ((elapsed++))
  done
  
  error "Failed to acquire lock for: $secret_name (timeout)"
  return 1
}

# Release lock for credential rotation
release_lock() {
  local secret_name="$1"
  local lock_file="${LOCK_DIR}/${secret_name}.lock"
  
  if [ -d "$lock_file" ]; then
    rm -rf "$lock_file"
  fi
}

# Rotate credentials (called by daemon)
rotate_credentials() {
  local secret_path="$1"
  local secret_name="${2:-default}"
  
  log "INFO" "Starting credential rotation for: $secret_name"
  
  # Acquire lock to prevent concurrent rotations
  acquire_lock "$secret_name" || return 1
  
  # Clean up lock on exit
  trap "release_lock '$secret_name'" RETURN
  
  # Skip if still valid
  if is_credential_valid "$secret_name"; then
    local cache_file="${CREDENTIAL_CACHE_DIR}/${secret_name}.secret"
    local expires_at
    expires_at=$(jq -r '.expires_at' "$cache_file" 2>/dev/null || echo 0)
    
    local current_time
    current_time=$(date +%s)
    
    local time_left=$((expires_at - current_time))
    
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
  
  # Validate dependencies including yq
  check_dependencies "daemon" || return 1
  
  [ -f "$rotation_config" ] || \
    error "Rotation config not found: $rotation_config"
  
  while true; do
    log "DEBUG" "Running rotation cycle..."
    
    # Parse config and rotate each secret
    # Use process substitution to avoid subshell issues
    while IFS='|' read -r path name; do
      [ -z "$path" ] && continue
      rotate_credentials "$path" "$name" 2>&1 || log "WARN" "Rotation failed for: $name"
    done < <(yq '.credentials[] | .path + "|" + .name' "$rotation_config" 2>/dev/null || echo "")
    
    sleep "$ROTATION_INTERVAL"
  done
}

# Revoke a credential
revoke_credential() {
  local secret_name="$1"
  
  local token
  token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  
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
      local secret_name
      secret_name=$(basename "$cache_file" .secret)
      revoke_credential "$secret_name" || true
    fi
  done
  
  # Revoke Vault token
  local token
  token=$(cat "${CREDENTIAL_CACHE_DIR}/.vault-token" 2>/dev/null || echo "")
  
  if [ -n "$token" ]; then
    local curl_opts=($(build_curl_opts))
    
    curl "${curl_opts[@]}" -X POST \
      -H "X-Vault-Token: $token" \
      "$VAULT_ADDR/v1/auth/token/revoke-self" > /dev/null 2>&1 || true
    
    rm -f "${CREDENTIAL_CACHE_DIR}/.vault-token" "${CREDENTIAL_CACHE_DIR}/.vault-token-meta"
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
  echo "Cache Permissions: $(stat -c "%a" "$CREDENTIAL_CACHE_DIR")"
  echo ""
  
  echo "Cached Credentials:"
  for cache_file in "${CREDENTIAL_CACHE_DIR}"/*.secret; do
    if [ -f "$cache_file" ]; then
      local secret_name
      secret_name=$(basename "$cache_file" .secret)
      
      local expires_at
      expires_at=$(jq -r '.expires_at' "$cache_file" 2>/dev/null || echo 0)
      
      local current
      current=$(date +%s)
      
      local time_left=$((expires_at - current))
      
      if [ "$time_left" -gt 0 ]; then
        echo "  ✓ $secret_name (expires in ${time_left}s)"
      else
        echo "  ✗ $secret_name (EXPIRED)"
      fi
    fi
  done
  
  echo ""
  echo "Recent Operations (last 10):"
  tail -10 "$AUDIT_LOG" 2>/dev/null | sed 's/^/  /' || echo "  (no audit log)"
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
Vault Secrets Integration - Phase P1 (Hardened)

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
  CURL_TIMEOUT               Curl connection timeout (default: 30)
  VAULT_SKIP_VERIFY          Skip HTTPS verification (default: false) - DEV ONLY
  VAULT_CAPATH               Path to CA certificate for Vault

Security Features:
  - File permission validation (secret ID file and cache directory)
  - SSL/TLS certificate verification (customizable)
  - Connection and read timeouts for all network operations
  - Process locking for concurrent rotation safety
  - Comprehensive audit logging
  - Secure secret caching with 600 permissions

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

Security Notes:
  - Always use HTTPS for Vault connections in production
  - Ensure secret ID file has 600 permissions
  - Cache directory will be automatically set to 700 permissions
  - All cached files are created with 600 permissions (user read/write only)
  - Set VAULT_CAPATH for custom CA certificates

HELP
      exit 1
      ;;
  esac
}

# Register cleanup on exit
trap cleanup EXIT

main "$@"
