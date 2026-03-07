#!/bin/bash
set -u

# Disaster Recovery - Recover from Complete System Nuke
# Recovers application from Docker Hub backup with cascading registry fallback
# Usage: ./scripts/recover-from-nuke.sh <backup-tag>
# Example: ./scripts/recover-from-nuke.sh backup-20260305-020000

BACKUP_TAG="${1:?Backup tag required (e.g., backup-20260305-020000)}"

# Registry fallback chain (ordered by preference)
BACKUP_REGISTRIES=(
  "docker.io"
  "123456789.dkr.ecr.us-east-1.amazonaws.com"
  "us-east1-docker.pkg.dev/${GCP_PROJECT_ID:-your-project}/docker-hub-mirror"
)

# Exports
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
export RECOVERY_START_TIME=$(date +%s)

# === LOGGING & OUTPUT ===

log() { echo "[RECOVERY] $(date +'%H:%M:%S') $*"; }
pass() { echo "[SUCCESS] $(date +'%H:%M:%S') ✓ $*"; }
warn() { echo "[WARNING] $(date +'%H:%M:%S') ⚠ $*"; }
fail() { echo "[FAILURE] $(date +'%H:%M:%S') ✗ $*" >&2; exit 1; }

# === SECRET RETRIEVAL ===

get_docker_hub_credentials() {
  log "Retrieving Docker Hub credentials..."
  
  # Try multi-tier retrieval
  local docker_hub_pat
  docker_hub_pat=$(bash scripts/get-secret-with-fallback.sh \
    "docker-hub-pat" "gcp,aws,github,local" 2>/dev/null) || {
    warn "Multi-tier secret retrieval failed, checking environment..."
    docker_hub_pat="${DOCKER_HUB_PAT:-}"
  }
  
  if [[ -z "$docker_hub_pat" ]]; then
    fail "Could not retrieve Docker Hub PAT from any source"
  fi
  
  export DOCKER_HUB_PAT="$docker_hub_pat"
  pass "Docker Hub credentials retrieved"
}

# === REGISTRY HEALTH CHECK ===

check_registry_health() {
  local registry=$1
  
  case "$registry" in
    docker.io)
      curl -f https://hub.docker.com/v2/ --connect-timeout 5 --max-time 10 \
        >/dev/null 2>&1
      ;;
    *ecr*)
      aws ecr describe-repositories --region us-east-1 \
        >/dev/null 2>&1
      ;;
    *artifactregistry*)
      gcloud artifacts repositories list \
        >/dev/null 2>&1
      ;;
  esac
  
  return $?
}

# === MULTI-REGISTRY PULL WITH RETRY ===

attempt_pull_with_retries() {
  local registry=$1
  local image=$2
  local backup_tag=$3
  local max_attempts=3
  
  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    log "  Attempt $attempt/$max_attempts: $registry"
    
    # Exponential backoff: 1s, 2s, 4s
    local backoff_delay=$((2 ** (attempt - 1)))
    
    if [[ $attempt -gt 1 ]]; then
      log "  Waiting ${backoff_delay}s before retry..."
      sleep "$backoff_delay"
    fi
    
    # Attempt pull with timeout
    if timeout 60 docker pull "$registry/elevatediq/app-backup:$backup_tag" 2>/dev/null; then
      pass "Successfully pulled from $registry"
      return 0
    fi
  done
  
  warn "$registry: All retry attempts exhausted"
  return 1
}

# === CASCADE FAILOVER RECOVERY ===

recover_from_backup_with_fallback() {
  local backup_tag=$1
  
  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║  CASCADING REGISTRY FALLBACK RECOVERY      ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
  log "Backup tag: $backup_tag"
  log "Registry chain: ${#BACKUP_REGISTRIES[@]} registries available"
  echo ""
  
  # Attempt Docker Hub login
  log "Authenticating with Docker Hub..."
  if echo "$DOCKER_HUB_PAT" | docker login -u elevatediq --password-stdin 2>/dev/null; then
    pass "Docker Hub authentication successful"
  else
    warn "Docker Hub authentication failed, proceeding with available credentials"
  fi
  
  echo ""
  
  # Try each registry in sequence
  for registry in "${BACKUP_REGISTRIES[@]}"; do
    log "Checking registry health: $registry"
    
    if check_registry_health "$registry"; then
      log "Registry is HEALTHY, attempting pull..."
      
      if attempt_pull_with_retries "$registry" "elevatediq/app-backup" "$backup_tag"; then
        log "Re-tagging image for local use..."
        docker tag "$registry/elevatediq/app-backup:$backup_tag" "elevatediq/app-backup:recovered"
        
        local duration=$(( $(date +%s) - RECOVERY_START_TIME ))
        
        echo ""
        echo "╔════════════════════════════════════════════╗"
        echo "║  RECOVERY SUCCESSFUL                       ║"
        echo "║  Source: $registry"
        echo "║  Duration: ${duration}s                    │"
        echo "╚════════════════════════════════════════════╝"
        echo ""
        
        pass "Recovery complete via $registry"
        return 0
      fi
    else
      warn "Registry $registry is UNHEALTHY, trying next..."
    fi
    
    echo ""
  done
  
  # All registries exhausted
  warn "All registry mirrors exhausted, attempting emergency bootstrap..."
  
  if recover_from_git_state; then
    return 0
  fi
  
  fail "Recovery failed - no registries or git state available"
}

# === EMERGENCY BOOTSTRAP ===

recover_from_git_state() {
  log "Attempting recovery from git-stored state..."
  
  if [[ ! -f "Dockerfile.backup" ]]; then
    warn "No Dockerfile.backup found"
    return 1
  fi
  
  log "Building from Dockerfile.backup..."
  
  if docker build \
    -f Dockerfile.backup \
    -t elevatediq/app-backup:recovered \
    . >/dev/null 2>&1; then
    
    pass "Emergency recovery from git succeeded"
    return 0
  fi
  
  return 1
}

# === VERIFY RECOVERY ===

verify_recovery_success() {
  log "Verifying recovery..."
  echo ""
  
  # Check image exists
  if ! docker inspect elevatediq/app-backup:recovered >/dev/null 2>&1; then
    fail "Recovered image not found"
  fi
  
  pass "Image recovered and available"
  
  # Check Dockerfile.backup exists
  if [[ ! -f "Dockerfile.backup" ]]; then
    warn "Dockerfile.backup not found"
  else
    pass "Backup Dockerfile verified"
  fi
  
  # Check recovery scripts exist
  if [[ ! -f "scripts/verify-recovery.sh" ]]; then
    warn "Verification script not found"
  else
    pass "Recovery scripts verified"
  fi
  
  echo ""
  pass "Recovery verification complete"
  return 0
}

# === MAIN ENTRY POINT ===

main() {
  log "Starting Disaster Recovery procedure"
  log "$(date +'%A, %B %d, %Y at %H:%M:%S UTC')"
  echo ""
  
  # Step 1: Get credentials
  if ! get_docker_hub_credentials; then
    fail "Cannot proceed without credentials"
  fi
  
  echo ""
  
  # Step 2: Perform recovery with cascading failover
  if ! recover_from_backup_with_fallback "$BACKUP_TAG"; then
    fail "Cascading recovery failed "
  fi
  
  echo ""
  
  # Step 3: Verify recovery
  if ! verify_recovery_success; then
    fail "Recovery verification failed"
  fi
  
  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║  DISASTER RECOVERY COMPLETE                ║"
  echo "║  Application backup restored and ready     ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
}

# Execute recovery
main "$@"
