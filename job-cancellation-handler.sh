#!/usr/bin/env bash
# Graceful Job Cancellation Handler - Hardened Edition
# Phase P1: Implements SIGTERM-based job cancellation with process cleanup
#
# Features:
#   - SIGTERM signal handling for graceful shutdown
#   - Process tree cleanup with escalation
#   - Checkpoint/state saving before exit
#   - Graceful timeout enforcement
#   - Child process tracking and termination
#   - Process safety improvements
#   - Race condition prevention

JOB_WRAPPER_PID="${JOB_WRAPPER_PID:-$$}"
JOB_TIMEOUT="${JOB_TIMEOUT:-3600}"
GRACE_PERIOD="${GRACE_PERIOD:-30}"
SIGTERM_TIMEOUT="${SIGTERM_TIMEOUT:-60}"
CHECKPOINT_DIR="${CHECKPOINT_DIR:-.job-checkpoints}"
PGID="${PGID:-$(ps -o pgid= -p $$ | tr -d ' ')}"

mkdir -p "$CHECKPOINT_DIR"
chmod 700 "$CHECKPOINT_DIR" 2>/dev/null || true

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Trap and handle SIGTERM
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

# Handle SIGINT (Ctrl+C)
handle_sigint() {
  log "⚠️  SIGINT received - initiating graceful shutdown"
  
  # Same as SIGTERM but treat as user interrupt
  handle_sigterm
}

# Save job state before terminating
save_checkpoint() {
  local checkpoint_file="${CHECKPOINT_DIR}/job-${JOB_WRAPPER_PID}.checkpoint"
  
  log "💾 Saving checkpoint: $checkpoint_file"
  
  # Get child process count safely
  local child_count=0
  if command -v pgrep &>/dev/null; then
    child_count=$(pgrep -P "$JOB_WRAPPER_PID" 2>/dev/null | wc -l)
  fi
  
  # Create checkpoint JSON carefully
  cat > "$checkpoint_file.tmp" <<EOF
{
  "job_id": "$JOB_WRAPPER_PID",
  "timestamp": "$(date -Iseconds)",
  "status": "cancelled",
  "pgid": $PGID,
  "shell_pid": $$,
  "signal": "SIGTERM",
  "children": $child_count
}
EOF
  
  # Atomic move
  mv -f "$checkpoint_file.tmp" "$checkpoint_file" 2>/dev/null || \
    log "⚠️  Failed to save checkpoint to: $checkpoint_file"
  
  chmod 600 "$checkpoint_file" 2>/dev/null || true
  
  # Also save environment for potential recovery
  env > "${checkpoint_file}.env" 2>/dev/null || true
  chmod 600 "${checkpoint_file}.env" 2>/dev/null || true
  
  log "✓ Checkpoint saved"
}

# Get all child processes safely
get_child_pids() {
  local target_pid="${1:-$JOB_WRAPPER_PID}"
  
  if ! command -v pgrep &>/dev/null; then
    return 0
  fi
  
  pgrep -P "$target_pid" 2>/dev/null || echo ""
}

# Graceful termination sequence with escalation
graceful_terminate() {
  log "🔄 Beginning graceful termination sequence..."
  
  local children
  children=$(get_child_pids)
  
  if [ -z "$children" ]; then
    log "  ℹ️  No child processes to terminate"
    return 0
  fi
  
  # Phase 1: SIGTERM to job process itself first
  log "  → Phase 1: Sending SIGTERM to job process $JOB_WRAPPER_PID..."
  
  if kill -0 "$JOB_WRAPPER_PID" 2>/dev/null; then
    kill -TERM "$JOB_WRAPPER_PID" 2>/dev/null || true
  fi
  
  # Also send to process group if different
  if [ "$PGID" != "$JOB_WRAPPER_PID" ]; then
    log "  → Phase 1b: Sending SIGTERM to process group -$PGID..."
    kill -TERM "-$PGID" 2>/dev/null || true
  fi
  
  local wait_time=0
  while [ $wait_time -lt $GRACE_PERIOD ]; do
    children=$(get_child_pids)
    
    if [ -z "$children" ]; then
      log "  ✓ All processes terminated gracefully"
      return 0
    fi
    
    sleep 1
    ((wait_time++))
  done
  
  # Phase 2: SIGKILL (forced termination)
  log "  ⚠️  Grace period expired ($GRACE_PERIOD seconds), sending SIGKILL..."
  
  children=$(get_child_pids)
  
  for child_pid in $children; do
    # Verify process still exists before killing
    if kill -0 "$child_pid" 2>/dev/null; then
      log "    → Killing process: $child_pid"
      kill -9 "$child_pid" 2>/dev/null || true
    fi
  done
  
  sleep 1
  
  # Verify main job process is terminated
  if kill -0 "$JOB_WRAPPER_PID" 2>/dev/null; then
    log "    → Force-killing main job: $JOB_WRAPPER_PID"
    kill -9 "$JOB_WRAPPER_PID" 2>/dev/null || true
  fi
  
  # Final verification
  local remaining
  remaining=$(get_child_pids | wc -l || echo 0)
  
  if [ "$remaining" -eq 0 ]; then
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
  
  # Don't aggressively close file descriptors
  # Let the OS handle them when process exits
  # Closing them during signal handlers can cause issues
  
  log "✓ Cleanup complete"
}

# Execute job with signal handlers
run_job() {
  local job_command="$*"
  
  log "🚀 Starting job: $job_command"
  log "   Job timeout: ${JOB_TIMEOUT}s"
  log "   Grace period: ${GRACE_PERIOD}s"
  
  # Create new process group for the job
  set -m
  
  # Run job in background so we can monitor it
  eval "$job_command" &
  local job_pid=$!
  
  # Store job PID for use in handlers
  JOB_WRAPPER_PID=$job_pid
  export JOB_WRAPPER_PID
  
  # Register signal handlers
  trap handle_sigterm SIGTERM
  trap handle_sigint SIGINT
  trap handle_sigterm SIGQUIT
  
  # Wait for job with timeout using a more robust method
  local timeout_remaining=$JOB_TIMEOUT
  local exit_code=0
  
  while kill -0 $job_pid 2>/dev/null; do
    if [ $timeout_remaining -le 0 ]; then
      log "⏱️  Job timeout exceeded ($JOB_TIMEOUT seconds)"
      
      # Send SIGTERM first
      kill -TERM $job_pid 2>/dev/null || true
      graceful_terminate
      
      # Wait for graceful shutdown
      sleep 5
      
      # Force kill if still running
      if kill -0 $job_pid 2>/dev/null; then
        log "❌ Job still running after SIGTERM, force killing..."
        kill -9 $job_pid 2>/dev/null || true
      fi
      
      return 124  # Timeout exit code
    fi
    
    sleep 1
    ((timeout_remaining--))
  done
  
  # Get job exit status
  wait $job_pid 2>/dev/null || true
  exit_code=$?
  
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
  local target_pid="$1"
  
  if [ -z "$target_pid" ]; then
    log "No job process ID provided"
    return 1
  fi
  
  # Check if process exists
  if kill -0 "$target_pid" 2>/dev/null; then
    log "✓ Job $target_pid is running"
    
    # Additional check: verify it's not a zombie
    local status
    status=$(ps -o stat= -p "$target_pid" 2>/dev/null | grep -o "^.")
    
    if [ "$status" = "Z" ]; then
      log "⚠️  Job $target_pid is a zombie process"
      return 2
    fi
    
    return 0
  else
    log "✗ Job $target_pid is not running"
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
Graceful Job Cancellation Handler - Hardened Edition

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
  SIGINT  - Ctrl+C, initiates graceful shutdown
  SIGQUIT - Terminal quit, initiates graceful shutdown
  SIGKILL - Forced termination if grace period exceeded (forced by kernel)

Exit Codes:
  0   - Job completed successfully
  1   - Job failed
  2   - Job is zombie (likely not running)
  124 - Job timeout exceeded
  143 - Job terminated by SIGTERM

Examples:
  job-cancellation-handler wrapper "tests" "pytest tests/"
  job-cancellation-handler check "job-12345"
  JOB_TIMEOUT=600 job-cancellation-handler wrapper "build" "docker build ."

Features:
  ✓ Graceful SIGTERM handling with checkpoint saving
  ✓ Process tree cleanup with escalation (SIGTERM → SIGKILL)
  ✓ Timeout enforcement with configurable grace period
  ✓ Zombie process detection
  ✓ Environment snapshot for debugging
  ✓ Safe process state verification
  ✓ Signal handler coordination (SIGTERM, SIGINT, SIGQUIT)

HELP
      exit 1
      ;;
  esac
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  main "$@"
fi
