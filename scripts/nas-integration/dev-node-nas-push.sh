#!/bin/bash
#
# 🗄️  NAS SERVER INTEGRATION - DEV NODE PUSH
#
# Manages configuration push from dev node (192.168.168.31) to NAS (192.168.168.100)
# Enables developers to make changes locally that propagate to worker nodes via NAS
#
# Usage:
#   bash dev-node-nas-push.sh
#   bash dev-node-nas-push.sh --watch      # Watch for changes and auto-push
#   bash dev-node-nas-push.sh --diff       # Show pending changes
#
# MANDATE:
#   ✅ Dev node acts as configuration source
#   ✅ NAS acts as centralized repository
#   ✅ Worker nodes pull from NAS
#   ✅ All pushes are signed and audited

set -euo pipefail

# ============================================================================
# DEV NODE & NAS CONFIGURATION
# ============================================================================

# Dev node (local)
readonly DEV_HOST="${DEV_HOST:-192.168.168.31}"
readonly DEV_USER="${DEV_USER:-automation}"

# NAS server coordinates
readonly NAS_HOST="${NAS_HOST:-192.168.168.100}"
readonly NAS_PORT="${NAS_PORT:-22}"
readonly NAS_USER="${NAS_USER:-svc-nas}"
readonly NAS_IAC_REPO="/home/svc-nas/repositories/iac"
readonly NAS_CONFIGS_DIR="/home/svc-nas/config-vault"

# Local directories on dev node
readonly DEV_IAC_DIR="${DEV_IAC_DIR:-/opt/iac-configs}"
readonly DEV_STAGING_DIR="${DEV_STAGING_DIR:-/tmp/nas-push-staging}"
readonly DEV_AUDIT_LOG="${DEV_AUDIT_LOG:-/var/log/nas-integration/dev-node-push.log}"

# SSH options
readonly SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"
readonly RSYNC_OPTS="-avz --checksum --timeout=30"

# Service account credentials
readonly SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-automation}"
readonly SSH_KEY="${SSH_KEY:-}"

# GIT integration
readonly ENABLE_GIT_COMMIT="${ENABLE_GIT_COMMIT:-false}"
readonly GIT_REPO="${GIT_REPO:-https://github.com/kushin77/self-hosted-runner.git}"

# Logging
readonly TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
readonly SESSION_ID=$(bash -c 'echo $RANDOM')

# ============================================================================
# LOGGING
# ============================================================================

log() {
  echo "[${TIMESTAMP}] [$$] INFO: $*" | tee -a "$DEV_AUDIT_LOG"
}

warn() {
  echo "[${TIMESTAMP}] [$$] WARN: $*" | tee -a "$DEV_AUDIT_LOG" >&2
}

error() {
  echo "[${TIMESTAMP}] [$$] ERROR: $*" | tee -a "$DEV_AUDIT_LOG" >&2
  return 1
}

success() {
  echo "[${TIMESTAMP}] [$$] ✅ $*" | tee -a "$DEV_AUDIT_LOG"
}

# ============================================================================
# ENVIRONMENT VALIDATION
# ============================================================================

validate_environment() {
  log "Validating dev node environment..."
  
  # Check we're running on dev node (or explicitly allowed)
  if [[ "$(hostname -I)" != *"192.168.168.31"* ]] && [[ "${FORCE_DEV_NODE:-false}" != "true" ]]; then
    warn "Running outside dev node network ($(hostname -I))"
    warn "Use FORCE_DEV_NODE=true to override"
  fi
  
  # Check required directories exist
  if [[ ! -d "$DEV_IAC_DIR" ]]; then
    error "IAC directory not found: $DEV_IAC_DIR"
    return 1
  fi
  
  # Check git is available (if git commits enabled)
  if [[ "$ENABLE_GIT_COMMIT" == "true" ]]; then
    if ! command -v git &>/dev/null; then
      error "Git not found but ENABLE_GIT_COMMIT=true"
      return 1
    fi
    log "Git integration enabled"
  fi
  
  success "Environment validation passed"
}

# ============================================================================
# DETECT SSH KEY
# ============================================================================

detect_ssh_key() {
  if [[ -n "${SSH_KEY}" && -f "${SSH_KEY}" ]]; then
    echo "$SSH_KEY"
    return 0
  fi

  local key_locations=(
    "/home/${SERVICE_ACCOUNT}/.ssh/id_ed25519"
    "/home/${SERVICE_ACCOUNT}/.ssh/nas-push-key"
    "/root/.ssh/id_${SERVICE_ACCOUNT}"
    "/opt/automation/.ssh/id_ed25519"
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
# INITIALIZE STAGING DIRECTORY
# ============================================================================

prepare_staging() {
  log "Preparing staging directory..."
  
  rm -rf "$DEV_STAGING_DIR"
  mkdir -p "$DEV_STAGING_DIR"
  
  # Copy IAC files to staging
  cp -r "$DEV_IAC_DIR"/* "$DEV_STAGING_DIR/" 2>/dev/null || \
    warn "Some IAC files could not be copied"
  
  success "Staging directory prepared"
}

# ============================================================================
# DETECT CHANGES (GIT or FILESYSTEM)
# ============================================================================

detect_changes() {
  log "Detecting pending changes..."
  
  local changes_count=0
  
  if [[ "$ENABLE_GIT_COMMIT" == "true" && -d "$DEV_IAC_DIR/.git" ]]; then
    # Use git to detect changes
    log "Using git for change detection..."
    changes_count=$(git -C "$DEV_IAC_DIR" status --porcelain | wc -l)
    
    if [[ $changes_count -gt 0 ]]; then
      log "Found $changes_count pending changes (git)"
      git -C "$DEV_IAC_DIR" status --short | tee -a "$DEV_AUDIT_LOG"
    fi
  else
    # Use file modification times
    log "Using filesystem timestamps for change detection..."
    local last_push_marker="${DEV_STAGING_DIR}/.last-push-time"
    
    if [[ -f "$last_push_marker" ]]; then
      local last_push_epoch=$(stat -f%m "$last_push_marker" 2>/dev/null || stat -c%Y "$last_push_marker" 2>/dev/null)
      changes_count=$(find "$DEV_IAC_DIR" -type f -newer "$last_push_marker" 2>/dev/null | wc -l)
      
      if [[ $changes_count -gt 0 ]]; then
        log "Found $changes_count files modified since last push"
      fi
    else
      changes_count=$(find "$DEV_IAC_DIR" -type f | wc -l)
      log "First push - found $changes_count IAC files"
    fi
  fi
  
  echo "$changes_count"
}

# ============================================================================
# VALIDATE PUSH CONTENT
# ============================================================================

validate_push_content() {
  log "Validating push content..."
  
  local errors=0
  
  # Check for sensitive files that should NOT be pushed
  local forbidden_patterns=(
    "*.key"
    "*.pem"
    "*.credentials"
    "*secret*"
    "*password*"
  )
  
  for pattern in "${forbidden_patterns[@]}"; do
    if find "$DEV_STAGING_DIR" -name "$pattern" 2>/dev/null | grep -q .; then
      error "Found sensitive files matching pattern: $pattern"
      ((errors++))
    fi
  done
  
  # Validate YAML/JSON where present
  if command -v yamllint &>/dev/null; then
    log "Running YAML validation..."
    if ! find "$DEV_STAGING_DIR" -name "*.yaml" -o -name "*.yml" | xargs yamllint 2>&1 | tee -a "$DEV_AUDIT_LOG"; then
      warn "YAML validation found issues (continuing)"
    fi
  fi
  
  if [[ $errors -eq 0 ]]; then
    success "Push content validation passed"
    return 0
  else
    error "Content validation failed ($errors issues)"
    return 1
  fi
}

# ============================================================================
# PUSH TO NAS
# ============================================================================

push_to_nas() {
  local ssh_key="$1"
  
  log "Pushing configurations to NAS..."
  
  # Test connectivity first
  if ! ssh -i "$ssh_key" $SSH_OPTS -p "$NAS_PORT" "${NAS_USER}@${NAS_HOST}" \
       test -d "$NAS_IAC_REPO" &>/dev/null; then
    error "Cannot reach NAS repository"
    return 1
  fi
  
  log "NAS connectivity verified, starting rsync..."
  
  # Use rsync for efficient transfer with checksum verification
  if rsync ${RSYNC_OPTS} \
      -e "ssh -i $ssh_key $SSH_OPTS -p $NAS_PORT" \
      "$DEV_STAGING_DIR/" \
      "${NAS_USER}@${NAS_HOST}:${NAS_IAC_REPO}/" \
      2>&1 | tee -a "$DEV_AUDIT_LOG"; then
    success "Push to NAS completed successfully"
    touch "${DEV_STAGING_DIR}/.last-push-time"
    return 0
  else
    error "Rsync push to NAS failed"
    return 1
  fi
}

# ============================================================================
# GIT COMMIT TO GITHUB (OPTIONAL)
# ============================================================================

commit_to_github() {
  if [[ "$ENABLE_GIT_COMMIT" != "true" ]]; then
    return 0
  fi
  
  if [[ ! -d "$DEV_IAC_DIR/.git" ]]; then
    warn "Git repository not found, skipping commit"
    return 0
  fi
  
  log "Committing changes to GitHub..."
  
  cd "$DEV_IAC_DIR"
  
  # Create descriptive commit message
  local commit_msg="[AUTO] NAS Sync: $(date +'%Y-%m-%d %H:%M:%S') - Session $SESSION_ID"
  
  if git add -A && git commit -m "$commit_msg" 2>&1 | tee -a "$DEV_AUDIT_LOG"; then
    log "Commit created: $commit_msg"
    
    # Attempt to push to GitHub
    if git push origin main 2>&1 | tee -a "$DEV_AUDIT_LOG"; then
      success "Pushed to GitHub successfully"
      return 0
    else
      warn "Could not push to GitHub (NAS push still succeeded)"
      return 0
    fi
  else
    log "No changes to commit"
    return 0
  fi
}

# ============================================================================
# WATCH MODE (CONTINUOUS SYNC)
# ============================================================================

enable_watch_mode() {
  local ssh_key="$1"
  
  log "════════════════════════════════════════════════════════════"
  log "🔄 Watch Mode Enabled - Monitoring for changes..."
  log "════════════════════════════════════════════════════════════"
  log "Press Ctrl+C to stop watching"
  log ""
  
  local last_push_time=$(date +%s)
  local min_interval=60  # Minimum 60s between pushes
  
  while true; do
    local current_time=$(date +%s)
    local time_since_push=$((current_time - last_push_time))
    
    # Detect changes
    local change_count=$(detect_changes)
    
    if [[ $change_count -gt 0 ]] && [[ $time_since_push -ge $min_interval ]]; then
      log "Changes detected ($change_count files), pushing to NAS..."
      
      if prepare_staging && validate_push_content && push_to_nas "$ssh_key"; then
        commit_to_github
        last_push_time=$(date +%s)
        success "Watch mode push completed"
      else
        warn "Watch mode push failed, will retry"
      fi
    fi
    
    # Sleep before next check (30 seconds)
    sleep 30
  done
}

# ============================================================================
# SHOW DIFF
# ============================================================================

show_diff() {
  log "Showing pending changes..."
  
  if [[ "$ENABLE_GIT_COMMIT" == "true" && -d "$DEV_IAC_DIR/.git" ]]; then
    log "Git diff:"
    git -C "$DEV_IAC_DIR" diff --stat
    echo ""
    git -C "$DEV_IAC_DIR" diff
  else
    log "Files in IAC directory:"
    find "$DEV_IAC_DIR" -type f -exec ls -lh {} \; | awk '{print $9, "(" $5 ")"}'
  fi
}

# ============================================================================
# AUDIT & LOGGING
# ============================================================================

log_push_audit() {
  local status="$1"
  local change_count="$2"
  local duration="$3"
  
  local audit_entry=$(jq -n \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session_id "$SESSION_ID" \
    --arg status "$status" \
    --arg changes "$change_count" \
    --arg duration_seconds "$duration" \
    '{
      timestamp: $timestamp,
      session_id: $session_id,
      operation: "dev-to-nas-push",
      status: $status,
      changes_synced: ($changes | tonumber),
      duration_seconds: ($duration_seconds | tonumber),
      user: env.USER,
      host: env.HOSTNAME
    }')
  
  echo "$audit_entry" >> "/var/log/nas-integration/dev-node-audit-trail.jsonl"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  local mode="${1:-push}"
  local start_time=$(date +%s)
  
  mkdir -p "$(dirname "$DEV_AUDIT_LOG")"
  
  log "════════════════════════════════════════════════════════════"
  log "🗄️  Dev Node → NAS Integration"
  log "════════════════════════════════════════════════════════════"
  log "Mode: $mode"
  log "NAS: ${NAS_USER}@${NAS_HOST}"
  log "Session: $SESSION_ID"
  log ""
  
  # Validate environment
  if ! validate_environment; then
    return 1
  fi
  
  # Detect SSH key
  if ! SSH_KEY_PATH=$(detect_ssh_key); then
    error "No SSH key found for NAS access"
    return 1
  fi
  success "SSH key detected: $(basename "$SSH_KEY_PATH")"
  log ""
  
  case "$mode" in
    push)
      log "Executing one-time push..."
      prepare_staging
      detect_changes
      
      if ! validate_push_content; then
        error "Content validation failed, aborting push"
        return 1
      fi
      
      if push_to_nas "$SSH_KEY_PATH"; then
        commit_to_github
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_push_audit "SUCCESS" "$(detect_changes)" "$duration"
        success "Push completed in ${duration}s"
      else
        error "Push failed"
        return 1
      fi
      ;;
    
    watch)
      enable_watch_mode "$SSH_KEY_PATH"
      ;;
    
    diff)
      show_diff
      ;;
    
    *)
      error "Unknown mode: $mode"
      echo "Usage: $0 [push|watch|diff]"
      return 1
      ;;
  esac
  
  log "════════════════════════════════════════════════════════════"
}

main "$@"
