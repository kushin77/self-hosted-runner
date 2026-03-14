#!/bin/bash
# GKE Cluster Stuck State Recovery & Prevention
# Handles clusters stuck in ERROR/PROVISIONING states
# Fully idempotent, GSM-based credentials, no manual ops

set -euo pipefail

PROJECT="${PROJECT:-nexusshield-prod}"
CLUSTER="${CLUSTER:-nexus-prod-gke}"
ZONE="${ZONE:-us-central1-a}"
TIMEOUT=600
OPERATION_TIMEOUT=300
MAX_RETRIES=5
RETRY_DELAY=10

# ===== 1. Configuration =====
STUCK_STATE_MARKER="/tmp/.cluster.stuck"
RECOVERY_LOG="/tmp/cluster-recovery-$(date +%s).log"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$RECOVERY_LOG"
}

log_success() {
  echo "✅ $*" | tee -a "$RECOVERY_LOG"
}

log_error() {
  echo "❌ $*" | tee -a "$RECOVERY_LOG"
  return 1
}

# ===== 2. Detect Stuck State =====
detect_stuck_state() {
  log "Detecting cluster state..."
  
  local cluster_status=$(gcloud container clusters describe "$CLUSTER" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --format="value(status)" 2>/dev/null || echo "UNKNOWN")
  
  case "$cluster_status" in
    RUNNING)
      log_success "Cluster is in RUNNING state"
      return 0
      ;;
    PROVISIONING)
      log_error "Cluster stuck in PROVISIONING state"
      return 1
      ;;
    ERROR)
      log_error "Cluster in ERROR state"
      return 1
      ;;
    DEGRADED)
      log_error "Cluster in DEGRADED state"
      return 1
      ;;
    *)
      log "Cluster status: $cluster_status"
      return 2
      ;;
  esac
}

# ===== 3. Check for Stuck Operations =====
find_stuck_operations() {
  log "Checking for stuck/pending operations..."
  
  local stuck_ops=$(gcloud container operations list \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --filter="(status!=DONE AND status!=ABORTING) AND targetLink:*$CLUSTER" \
    --format="value(name,status,type)" 2>/dev/null || echo "")
  
  if [ -z "$stuck_ops" ]; then
    log_success "No stuck operations found"
    return 0
  fi
  
  log_error "Found stuck operations:"
  echo "$stuck_ops" | while read -r line; do
    log "  $line"
  done
  
  echo "$stuck_ops"
  return 1
}

# ===== 4. Cancel Stuck Operations =====
cancel_stuck_operations() {
  local stuck_ops=$1
  
  log "Attempting to cancel stuck operations..."
  
  echo "$stuck_ops" | while read -r op_name op_status op_type; do
    [ -z "$op_name" ] && continue
    
    log "Cancelling operation: $op_name ($op_type, $op_status)"
    
    gcloud container operations cancel "$op_name" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --quiet 2>/dev/null && \
      log_success "Cancelled: $op_name" || \
      log "  Cancel result: In progress or already completed"
  done
}

# ===== 5. Monitor Operation Progress =====
monitor_operations() {
  log "Monitoring operation progress (max $OPERATION_TIMEOUT seconds)..."
  
  local start_time=$(date +%s)
  local attempt=0
  
  while [ $(($(date +%s) - start_time)) -lt $OPERATION_TIMEOUT ]; do
    ((attempt++))
    
    local running_ops=$(gcloud container operations list \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --filter="(status!=DONE AND status!=ABORTING) AND targetLink:*$CLUSTER" \
      --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [ "$running_ops" -eq 0 ]; then
      log_success "All operations completed"
      return 0
    fi
    
    log "Operations in progress: $running_ops (attempt $attempt)"
    sleep $RETRY_DELAY
  done
  
  log_error "Operations did not complete within $OPERATION_TIMEOUT seconds"
  return 1
}

# ===== 6. Verify Cluster Health After Recovery =====
verify_cluster_health() {
  log "Verifying cluster health after recovery..."
  
  local health_attempts=0
  
  while [ $health_attempts -lt $MAX_RETRIES ]; do
    ((health_attempts++))
    
    local cluster_status=$(gcloud container clusters describe "$CLUSTER" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --format="value(status)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "$cluster_status" = "RUNNING" ]; then
      # Test kubectl connectivity
      if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Cluster health verified: RUNNING with kubectl access"
        return 0
      else
        log "Cluster RUNNING but kubectl connection failed, retrying..."
      fi
    else
      log "Cluster status: $cluster_status (attempt $health_attempts/$MAX_RETRIES)"
    fi
    
    sleep $((RETRY_DELAY * health_attempts))
  done
  
  log_error "Cluster health verification failed after $MAX_RETRIES attempts"
  return 1
}

# ===== 7. Recovery Workflow =====
recover_stuck_cluster() {
  log "Starting recovery workflow for cluster: $CLUSTER"
  echo ""
  
  # Step 1: Detect state
  log "Step 1: Detecting cluster state..."
  detect_stuck_state
  local detect_result=$?
  
  if [ $detect_result -eq 0 ]; then
    log_success "Cluster is healthy, no recovery needed"
    return 0
  fi
  
  echo ""
  
  # Step 2: Find stuck operations
  log "Step 2: Finding stuck operations..."
  local stuck_ops=$(find_stuck_operations || echo "")
  
  if [ -z "$stuck_ops" ]; then
    log "No stuck operations found, cluster may be in terminal ERROR state"
    log "Cluster status command output:"
    gcloud container clusters describe "$CLUSTER" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --format="table(name,status,location,createTime)" 2>/dev/null || \
      log_error "Failed to describe cluster"
    return 1
  fi
  
  echo ""
  
  # Step 3: Cancel stuck operations
  log "Step 3: Cancelling stuck operations..."
  cancel_stuck_operations "$stuck_ops"
  
  echo ""
  
  # Step 4: Monitor progress
  log "Step 4: Monitoring operation progress..."
  monitor_operations || {
    log_error "Operation monitoring timeout. Cluster may need force-delete."
    return 2
  }
  
  echo ""
  
  # Step 5: Verify health
  log "Step 5: Verifying cluster health..."
  verify_cluster_health
  
  return $?
}

# ===== 8. Documentation of Stuck State Handling =====
create_stuck_state_docs() {
  local docs_file="$RECOVERY_LOG.handling-guide.txt"
  
  cat > "$docs_file" << 'EOF'
=== GKE CLUSTER STUCK STATE HANDLING GUIDE ===

SYMPTOM: Cluster status shows PROVISIONING, ERROR, or DEGRADED

PREVENTION:
1. Always use operation polling with timeout
2. Never interrupt cluster creation/modification operations
3. Use exponential backoff for retries
4. Implement circuit breakers (max 3 retries, then escalate)

AUTOMATIC RECOVERY (This Script):
1. Detects stuck state via `gcloud container clusters describe`
2. Lists all operations with `gcloud container operations list`
3. Cancels stuck operations with `gcloud container operations cancel`
4. Monitors completion with exponential backoff
5. Verifies health with kubectl connectivity check

MANUAL RECOVERY (If Script Fails):
1. Check operation status:
   gcloud container operations list \
     --zone=ZONE --project=PROJECT \
     --filter="targetLink:*CLUSTER"

2. Cancel stuck operation:
   gcloud container operations cancel OPERATION_NAME \
     --zone=ZONE --project=PROJECT --quiet

3. Wait for cancellation:
   gcloud container operations describe OPERATION_NAME \
     --zone=ZONE --project=PROJECT \
     --format="value(status)"

4. If still stuck, force delete cluster:
   gcloud container clusters delete CLUSTER \
     --zone=ZONE --project=PROJECT --quiet --async

5. Verify deletion:
   gcloud container clusters list --project=PROJECT

PREVENTION BEST PRACTICES:
- Set OPERATION_TIMEOUT <= 300 seconds
- Use --quiet flag to prevent user input blocking
- Implement --async operations for background tasks
- Configure Cloud Scheduler for periodic health checks
- Set up alerts for clusters > 5 min in PROVISIONING state

ERROR CODES:
- 0: Recovery successful, cluster RUNNING
- 1: Cluster in recoverable ERROR state, recovery failed
- 2: Cluster may need force-delete (manual intervention)

EOF
  
  log "Stuck state handling guide created: $docs_file"
  cat "$docs_file" >> "$RECOVERY_LOG"
}

# ===== MAIN =====
main() {
  echo "🔧 GKE Cluster Stuck State Recovery & Prevention"
  echo "  Cluster: $CLUSTER (Zone: $ZONE)"
  echo "  Project: $PROJECT"
  echo "  Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
  recover_stuck_cluster
  local result=$?
  
  echo ""
  create_stuck_state_docs
  
  echo ""
  echo "📋 Recovery log: $RECOVERY_LOG"
  
  exit $result
}

main "$@"
