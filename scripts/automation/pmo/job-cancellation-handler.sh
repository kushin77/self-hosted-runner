#!/usr/bin/env bash
set -euo pipefail

# Graceful Job Cancellation Handler
# Phase P1: Implements SIGTERM-based job cancellation with process cleanup
#
# Features:
#   - SIGTERM signal handling for graceful shutdown
#   - Process tree cleanup with escalation
#   - Checkpoint/state saving before exit
#   - Graceful timeout enforcement
#   - Child process tracking and termination

JOB_WRAPPER_PID=$$
JOB_TIMEOUT="${JOB_TIMEOUT:-3600}"
GRACE_PERIOD="${GRACE_PERIOD:-30}"
SIGTERM_TIMEOUT="${SIGTERM_TIMEOUT:-60}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-.job-checkpoints}"

mkdir -p "$CHECKPOINT_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Trap SIGTERM and initiate graceful shutdown
handle_sigterm() {
  log "🛑 SIGTERM received - initiating graceful shutdown"
  
  # Create checkpoint file
  save_checkpoint
  
  # Terminate child processes gracefully
  graceful_terminate
  
  # Cleanup and exit
  cleanup
  
  exit 143  # Standard SIGTERM exit code
}

# Save job state before terminating
save_checkpoint() {
  local checkpoint_file="${CHECKPOINT_DIR}/job-${JOB_WRAPPER_PID}.checkpoint"
  
  log "💾 Saving checkpoint: $checkpoint_file"
  
  cat > "$checkpoint_file" <<EOF
{
  "job_id": "$JOB_WRAPPER_PID",
  "timestamp": "$(date -Iseconds)",
  "status": "cancelled",
  "pgid": $PGID,
  "shell_pid": $$,
  "signal": "SIGTERM",
  "children": $(get_child_pids | jq -R 'split("\n") | map(select(length > 0) | tonumber) | length')
}
EOF
  
  # Also save environment for potential recovery
  env > "${checkpoint_file}.env"
  
  log "✓ Checkpoint saved"
}

# Get all child processes
get_child_pids() {
  pgrep -P $JOB_WRAPPER_PID 2>/dev/null || echo ""
}

# Graceful termination sequence with escalation
graceful_terminate() {
  log "🔄 Beginning graceful termination sequence..."
  
  local children=$(get_child_pids)
  
  if [ -z "$children" ]; then
    log "  ℹ️  No child processes to terminate"
    return 0
  fi
  
  # Phase 1: SIGTERM (30 seconds)
  log "  → Phase 1: Sending SIGTERM to process group..."
  kill -TERM -$PGID 2>/dev/null || true
  
  local wait_time=0
  while [ $wait_time -lt $GRACE_PERIOD ]; do
    if ! get_child_pids > /dev/null 2>&1; then
      log "  ✓ All processes terminated gracefully"
      return 0
    fi
    
    sleep 1
    ((wait_time++))
  done
  
  # Phase 2: SIGKILL (forced termination)
  log "  ⚠️  Grace period expired, sending SIGKILL..."
  children=$(get_child_pids)
  
  for child_pid in $children; do
    log "    → Killing process: $child_pid"
    kill -9 "$child_pid" 2>/dev/null || true
  done
  
  sleep 1
  
  # Verify all terminated
  local remaining=$(get_child_pids | wc -l || echo 0)
  if [ $remaining -eq 0 ]; then
    log "  ✓ All processes terminated forcefully"
    return 0
  else
    log "  ❌ WARNING: $remaining processes still running after SIGKILL"
    return 1
  fi
}

# Cleanup resources
cleanup() {
  log "🧹 Cleaning up resources..."
  
  # Close file descriptors
  exec 2>&-
  exec 1>&-
  
  log "✓ Cleanup complete"
}

# Execute job with signal handlers
run_job() {
  local job_command="$@"
  
  log "🚀 Starting job: $job_command"
  log "   Job timeout: ${JOB_TIMEOUT}s"
  log "   Grace period: ${GRACE_PERIOD}s"
  
  # Create new process group for the job
  set -m
  
  # Run job in background so we can monitor it
  eval "$job_command" &
  local job_pid=$!
  
  # Register signal handler
  trap handle_sigterm SIGTERM
  
  # Wait for job with timeout
  local timeout_remaining=$JOB_TIMEOUT
  
  while kill -0 $job_pid 2>/dev/null; do
    if [ $timeout_remaining -le 0 ]; then
      log "⏱️  Job timeout exceeded ($JOB_TIMEOUT seconds)"
      kill -TERM $job_pid 2>/dev/null || true
      graceful_terminate
      
      # Wait final 10 seconds for cleanup
      sleep 10
      
      if kill -0 $job_pid 2>/dev/null; then
        log "❌ Job still running after timeout, force killing..."
        kill -9 $job_pid 2>/dev/null || true
      fi
      
      return 124  # Timeout exit code
    fi
    
    sleep 1
    ((timeout_remaining--))
  done
  
  # Get job exit status
  wait $job_pid
  local exit_code=$?
  
  log "✓ Job completed with exit code: $exit_code"
  
  return $exit_code
}

# Wrapper for use in GitHub Actions
github_actions_wrapper() {
  local job_name="$1"
  shift
  local job_command="$@"
  
  # Set GitHub Actions-specific environment
  export RUNNER_GRACEFUL_SHUTDOWN_ENABLED=true
  export JOB_NAME="$job_name"
  
  log "🏃 GitHub Actions Job: $job_name"
  
  # Run with timeout enforcement
  run_job "$job_command"
}

# Health check for running jobs
job_health_check() {
  local job_id="$1"
  
  if [ -z "$job_id" ]; then
    log "No job ID provided"
    return 1
  fi
  
  # Check if job is still running
  if get_child_pids > /dev/null 2>&1; then
    log "✓ Job $job_id is running"
    return 0
  else
    log "✗ Job $job_id is not running"
    return 1
  fi
}

# CLI interface
main() {
  case "${1:-help}" in
    wrapper)
      github_actions_wrapper "$2" "${@:3}"
      ;;
    check)
      job_health_check "${2:-.}"
      ;;
    cleanup-checkpoints)
      log "🧹 Cleaning up old checkpoints..."
      find "$CHECKPOINT_DIR" -name "*.checkpoint" -mtime +7 -delete
      log "✓ Cleanup complete"
      ;;
    *)
      cat <<'HELP'
Graceful Job Cancellation Handler

Usage:
  job-cancellation-handler wrapper <job-name> <command...>  Run wrapped job
  job-cancellation-handler check <job-id>                   Check job health
  job-cancellation-handler cleanup-checkpoints              Clean old checkpoints

Environment Variables:
  JOB_TIMEOUT         Maximum job duration in seconds (default: 3600)
  GRACE_PERIOD        SIGTERM grace period in seconds (default: 30)
  CHECKPOINT_DIR      Checkpoint storage directory (default: .job-checkpoints)

Signals:
  SIGTERM - Initiates graceful shutdown with checkpoint saving
  SIGKILL - Forced termination if grace period exceeded

Exit Codes:
  0   - Job completed successfully
  1   - Job failed
  124 - Job timeout exceeded
  143 - Job terminated by SIGTERM

Examples:
  job-cancellation-handler wrapper "tests" "pytest tests/"
  job-cancellation-handler check "job-12345"
  JOB_TIMEOUT=600 job-cancellation-handler wrapper "build" "docker build ."

HELP
      exit 1
      ;;
  esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
