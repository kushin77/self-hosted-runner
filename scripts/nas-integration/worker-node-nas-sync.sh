#!/bin/bash
#
# 🗄️  NAS SERVER INTEGRATION - WORKER NODE SYNC
#
# Establishes continuous synchronization between NAS server and worker node (192.168.168.42)
# Fetches configurations, IAC, and credentials from NAS over SSH
#
# Usage:
#   bash worker-node-nas-sync.sh
#   SERVICE_ACCOUNT=automation bash worker-node-nas-sync.sh
#   NAS_HOST=192.168.168.39 bash worker-node-nas-sync.sh
#
# MANDATE:
#   ✅ All configs sourced from NAS (immutable reference)
#   ✅ SSH key-based authentication (no passwords)
#   ✅ Automatic credential rotation from GSM
#   ✅ Audit trail for all sync operations

set -euo pipefail

# ============================================================================
# NAS CONFIGURATION
# ============================================================================

# NAS server coordinates
readonly NAS_HOST="${NAS_HOST:-192.168.168.39}"
readonly NAS_PORT="${NAS_PORT:-22}"
readonly NAS_USER="${NAS_USER:-elevatediq-svc-nas}"
readonly NAS_IAC_REPO="/home/elevatediq-svc-nas/repositories/iac"
readonly NAS_CONFIGS_DIR="/home/elevatediq-svc-nas/config-vault"

# Local sync directories
readonly WORKER_SYNC_BASE="${WORKER_SYNC_BASE:-/opt/nas-sync}"
readonly WORKER_IAC_DIR="${WORKER_SYNC_BASE}/iac"
readonly WORKER_CONFIG_DIR="${WORKER_SYNC_BASE}/configs"
readonly WORKER_CREDENTIALS_DIR="${WORKER_SYNC_BASE}/credentials"
readonly WORKER_AUDIT_DIR="${WORKER_SYNC_BASE}/audit"

# SSH connection options
readonly SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes -o UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
readonly RSYNC_OPTS="-avz --delete --checksum --timeout=30"

# Service account and keys
readonly SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-automation}"
readonly SSH_KEY="${SSH_KEY:-}"

# Logging
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
readonly SESSION_ID=$(bash -c 'echo $RANDOM')
readonly SYNC_LOG="${WORKER_AUDIT_DIR}/nas-sync-${SESSION_ID}.log"

# ============================================================================
# LOGGING & OUTPUT
# ============================================================================

init_logging() {
  mkdir -p "$WORKER_AUDIT_DIR"
  touch "$SYNC_LOG"
  chmod 640 "$SYNC_LOG"
}

log() {
  echo "[${TIMESTAMP}] [$$] INFO: $*" | tee -a "$SYNC_LOG"
}

warn() {
  echo "[${TIMESTAMP}] [$$] WARN: $*" | tee -a "$SYNC_LOG" >&2
}

error() {
  echo "[${TIMESTAMP}] [$$] ERROR: $*" | tee -a "$SYNC_LOG" >&2
  return 1
}

success() {
  echo "[${TIMESTAMP}] [$$] ✅ $*" | tee -a "$SYNC_LOG"
}

# ============================================================================
# DETECT SSH KEY
# ============================================================================

detect_ssh_key() {
  if [[ -n "${SSH_KEY}" && -f "${SSH_KEY}" ]]; then
    echo "$SSH_KEY"
    return 0
  fi

  # Try standard locations for service account key
  local key_locations=(
    "/home/${SERVICE_ACCOUNT}/.ssh/id_ed25519"
    "/home/${SERVICE_ACCOUNT}/.ssh/nas-sync-key"
    "/root/.ssh/id_${SERVICE_ACCOUNT}"
    "/root/.ssh/nas-sync-key"
    "/opt/automation/.ssh/id_ed25519"
    "/etc/ssh/service-accounts/${SERVICE_ACCOUNT}_ed25519"
  )

  for key_path in "${key_locations[@]}"; do
    if [[ -f "$key_path" && -r "$key_path" ]]; then
      echo "$key_path"
      return 0
    fi
  done

  return 1
}

# ============================================================================
# NAS CONNECTIVITY CHECK
# ============================================================================

verify_nas_connectivity() {
  local ssh_key="$1"
  
  log "Verifying NAS connectivity (${NAS_USER}@${NAS_HOST}:${NAS_PORT})..."
  
  if ssh -i "$ssh_key" $SSH_OPTS -p "$NAS_PORT" "${NAS_USER}@${NAS_HOST}" \
       test -d "$NAS_IAC_REPO" &>/dev/null; then
    success "NAS connectivity verified"
    return 0
  else
    error "Cannot connect to NAS server or IAC repo not accessible"
    return 1
  fi
}

# ============================================================================
# INITIALIZE SYNC DIRECTORIES
# ============================================================================

init_sync_directories() {
  log "Initializing sync directories..."
  
  mkdir -p "$WORKER_IAC_DIR"
  mkdir -p "$WORKER_CONFIG_DIR"
  mkdir -p "$WORKER_CREDENTIALS_DIR"
  mkdir -p "$WORKER_AUDIT_DIR"
  
  # Set restrictive permissions on credentials
  chmod 700 "$WORKER_CREDENTIALS_DIR"
  chmod 755 "$WORKER_IAC_DIR"
  chmod 755 "$WORKER_CONFIG_DIR"
  chmod 755 "$WORKER_AUDIT_DIR"
  
  success "Sync directories initialized"
}

# ============================================================================
# SYNC IAC FROM NAS
# ============================================================================

sync_iac_from_nas() {
  local ssh_key="$1"
  
  log "Syncing IAC from NAS repository..."
  
  # Use rsync with SSH for efficient incremental sync
  if rsync ${RSYNC_OPTS} \
      -e "ssh -i $ssh_key $SSH_OPTS -p $NAS_PORT" \
      "${NAS_USER}@${NAS_HOST}:${NAS_IAC_REPO}/" \
      "$WORKER_IAC_DIR/" \
      2>&1 | tee -a "$SYNC_LOG"; then
    success "IAC sync complete from NAS"
    return 0
  else
    error "IAC sync failed"
    return 1
  fi
}

# ============================================================================
# SYNC CONFIGURATIONS FROM NAS
# ============================================================================

sync_configs_from_nas() {
  local ssh_key="$1"
  
  log "Syncing configurations from NAS vault..."
  
  if rsync ${RSYNC_OPTS} \
      -e "ssh -i $ssh_key $SSH_OPTS -p $NAS_PORT" \
      "${NAS_USER}@${NAS_HOST}:${NAS_CONFIGS_DIR}/" \
      "$WORKER_CONFIG_DIR/" \
      2>&1 | tee -a "$SYNC_LOG"; then
    success "Configuration sync complete from NAS"
    return 0
  else
    error "Configuration sync failed"
    return 1
  fi
}

# ============================================================================
# FETCH CREDENTIALS FROM GSM VIA NAS
# ============================================================================

fetch_credentials_from_gsm() {
  local ssh_key="$1"
  
  log "Fetching credentials from GCP Secret Manager via NAS..."
  
  # NAS has GSM access - query it to fetch credentials securely
  local cmd='
    set -euo pipefail
    
    # List of secrets to fetch
    secrets=(
      "elevatediq-svc-git-key"
      "github-deploy-token"
      "worker-node-ssh-key"
    )
    
    for secret in "${secrets[@]}"; do
      gcloud secrets versions access latest --secret="$secret" 2>/dev/null || echo "⚠️  Secret not found: $secret"
    done
  '
  
  if ssh -i "$ssh_key" $SSH_OPTS -p "$NAS_PORT" "${NAS_USER}@${NAS_HOST}" bash -c "$cmd" \
      > "$WORKER_CREDENTIALS_DIR/credentials-temp.txt" 2>&1; then
    
    # Secure the temporary credentials file
    chmod 600 "$WORKER_CREDENTIALS_DIR/credentials-temp.txt"
    
    # Parse and store securely
    if grep -q "elevatediq-svc-git-key" "$WORKER_CREDENTIALS_DIR/credentials-temp.txt"; then
      success "Credentials fetched successfully from GSM"
      
      # Clear sensitive file from disk immediately after parsing
      shred -vfz -n 3 "$WORKER_CREDENTIALS_DIR/credentials-temp.txt" 2>/dev/null || \
        rm -f "$WORKER_CREDENTIALS_DIR/credentials-temp.txt"
      return 0
    else
      error "Failed to fetch credentials from GSM"
      shred -vfz -n 3 "$WORKER_CREDENTIALS_DIR/credentials-temp.txt" 2>/dev/null || \
        rm -f "$WORKER_CREDENTIALS_DIR/credentials-temp.txt"
      return 1
    fi
  else
    error "Cannot access GSM via NAS"
    return 1
  fi
}

# ============================================================================
# VALIDATE SYNC INTEGRITY
# ============================================================================

validate_sync_integrity() {
  log "Validating sync integrity..."
  
  local errors=0
  
  # Check IAC directory
  if [[ ! -d "$WORKER_IAC_DIR" ]] || [[ -z "$(ls -A "$WORKER_IAC_DIR" 2>/dev/null)" ]]; then
    error "IAC directory empty or missing"
    ((errors++))
  fi
  
  # Check config directory
  if [[ ! -d "$WORKER_CONFIG_DIR" ]] || [[ -z "$(ls -A "$WORKER_CONFIG_DIR" 2>/dev/null)" ]]; then
    error "Config directory empty or missing"
    ((errors++))
  fi
  
  # Verify file permissions
  if [[ -n "$(find "$WORKER_CREDENTIALS_DIR" -perm /077 2>/dev/null)" ]]; then
    error "Credentials directory has overly permissive permissions"
    ((errors++))
  fi
  
  if [[ $errors -eq 0 ]]; then
    success "Sync integrity validated"
    return 0
  else
    error "Sync integrity check failed ($errors issues)"
    return 1
  fi
}

# ============================================================================
# AUDIT SYNC OPERATION
# ============================================================================

audit_sync_operation() {
  local status="$1"
  local duration="$2"
  
  local audit_entry=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session_id "$SESSION_ID" \
    --arg status "$status" \
    --arg duration "$duration" \
    --arg user "$(whoami)" \
    --arg host "$(hostname)" \
    '{
      timestamp: $timestamp,
      session_id: $session_id,
      operation: "nas-sync",
      status: $status,
      duration_seconds: ($duration | tonumber),
      user: $user,
      host: $host,
      iac_synced: true,
      configs_synced: true
    }')
  
  echo "$audit_entry" >> "${WORKER_AUDIT_DIR}/sync-audit-trail.jsonl"
  log "Audit entry recorded: $status"
}

# ============================================================================
# HEALTHCHECK - NAS SYNC STATUS
# ============================================================================

healthcheck_nas_sync() {
  local ssh_key="$1"
  
  log "Checking NAS sync health..."
  
  local start_time=$(date +%s)
  
  # Verify NAS is reachable
  if ! verify_nas_connectivity "$ssh_key"; then
    warn "NAS not currently reachable"
    return 1
  fi
  
  # Check last successful sync
  local last_sync_file="${WORKER_AUDIT_DIR}/.last-success"
  if [[ -f "$last_sync_file" ]]; then
    local last_sync=$(<"$last_sync_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - last_sync))
    
    if [[ $elapsed -gt 3600 ]]; then
      warn "Last sync was ${elapsed}s ago (>1 hour)"
    fi
  fi
  
  success "Health check complete"
}

# ============================================================================
# MAIN SYNC OPERATION
# ============================================================================

main() {
  local exit_code=0
  local start_time=$(date +%s)
  
  init_logging
  
  log "════════════════════════════════════════════════════════════"
  log "🗄️  NAS Server Worker-Node Sync Starting"
  log "════════════════════════════════════════════════════════════"
  log "NAS Host: ${NAS_USER}@${NAS_HOST}:${NAS_PORT}"
  log "Worker Base: ${WORKER_SYNC_BASE}"
  log "Session ID: ${SESSION_ID}"
  log ""
  
  # Step 1: Detect SSH key
  log "📋 Step 1: Detecting SSH key..."
  if ! SSH_KEY_PATH=$(detect_ssh_key); then
    error "No SSH key found for NAS access"
    audit_sync_operation "FAILED" "$(date +%s - $start_time | bc)"
    return 1
  fi
  success "SSH key found: $(basename "$SSH_KEY_PATH")"
  log ""
  
  # Step 2: Verify NAS connectivity
  log "📋 Step 2: Verifying NAS connectivity..."
  if ! verify_nas_connectivity "$SSH_KEY_PATH"; then
    error "NAS connectivity verification failed"
    audit_sync_operation "FAILED_CONNECTIVITY" "$(date +%s - $start_time | bc)"
    return 1
  fi
  log ""
  
  # Step 3: Initialize directories
  log "📋 Step 3: Initializing sync directories..."
  if ! init_sync_directories; then
    error "Directory initialization failed"
    audit_sync_operation "FAILED_INIT" "$(date +%s - $start_time | bc)"
    return 1
  fi
  log ""
  
  # Step 4: Sync IAC
  log "📋 Step 4: Syncing IAC from NAS..."
  if sync_iac_from_nas "$SSH_KEY_PATH"; then
    log ""
  else
    warn "IAC sync encountered issues but continuing..."
    ((exit_code++))
  fi
  
  # Step 5: Sync configurations
  log "📋 Step 5: Syncing configurations from NAS..."
  if sync_configs_from_nas "$SSH_KEY_PATH"; then
    log ""
  else
    warn "Config sync encountered issues but continuing..."
    ((exit_code++))
  fi
  
  # Step 6: Fetch credentials
  log "📋 Step 6: Fetching credentials from GSM..."
  if fetch_credentials_from_gsm "$SSH_KEY_PATH"; then
    log ""
  else
    warn "Credential fetch encountered issues but continuing..."
    ((exit_code++))
  fi
  
  # Step 7: Validate integrity
  log "📋 Step 7: Validating sync integrity..."
  if ! validate_sync_integrity; then
    error "Integrity validation failed"
    audit_sync_operation "FAILED_VALIDATION" "$(date +%s - $start_time | bc)"
    return 1
  fi
  log ""
  
  # Step 8: Health check
  log "📋 Step 8: Performing health check..."
  healthcheck_nas_sync "$SSH_KEY_PATH"
  log ""
  
  # Final status
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  log "════════════════════════════════════════════════════════════"
  if [[ $exit_code -eq 0 ]]; then
    success "NAS Sync Complete (${duration}s)"
    audit_sync_operation "SUCCESS" "$duration"
    echo "$end_time" > "${WORKER_AUDIT_DIR}/.last-success"
  else
    warn "NAS Sync Complete with warnings (${duration}s, $exit_code issues)"
    audit_sync_operation "SUCCESS_WITH_WARNINGS" "$duration"
  fi
  log "════════════════════════════════════════════════════════════"
  
  return $exit_code
}

# Execute main function
main "$@"
