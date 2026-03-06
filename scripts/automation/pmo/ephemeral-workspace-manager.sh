#!/usr/bin/env bash
set -euo pipefail

# Ephemeral Workspace Manager
# Provides per-job isolated, transactional workspaces with guaranteed cleanup
#
# Features:
#   - Copy-on-write (CoW) overlay mounts for instant provisioning
#   - Per-job isolation (no carryover)
#   - Transactional cleanup with verification
#   - Failure artifact collection before purge

JOB_ID="${1:-}"
RUNNER_ROOT="${RUNNER_WORK_DIR:-.}"
WORKSPACE_ROOT="${RUNNER_ROOT}/_work"
EPHEMERAL_BASE="/mnt/ephemeral"
SNAPSHOT_DIR="${EPHEMERAL_BASE}/snapshots"
JOB_OVERLAY="${EPHEMERAL_BASE}/overlay-${JOB_ID}"

[ -n "$JOB_ID" ] || { echo "Usage: $0 <job_id>"; exit 1; }

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# safe_delete resolver (used for purging overlays)
SAFE_DELETE="$(pwd)/scripts/safe_delete.sh"
if [ ! -x "$SAFE_DELETE" ]; then SAFE_DELETE="$(dirname "$0")/../../scripts/safe_delete.sh"; fi
if [ ! -x "$SAFE_DELETE" ]; then SAFE_DELETE="$(dirname "$0")/../scripts/safe_delete.sh"; fi

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

# Create immutable baseline snapshot (one-time per runner)
create_baseline_snapshot() {
  if [ -f "${SNAPSHOT_DIR}/baseline.tar.zst" ]; then
    log "✓ Baseline snapshot already exists"
    return 0
  fi
  
  log "📸 Creating baseline snapshot..."
  mkdir -p "$SNAPSHOT_DIR"
  
  # Snapshot workspace (excluding _work dir)
  tar --exclude='_work' -czstd \
    -f "${SNAPSHOT_DIR}/baseline.tar.zst" \
    -C "$RUNNER_ROOT" .
  
  # Store hash for integrity verification
  sha256sum "${SNAPSHOT_DIR}/baseline.tar.zst" > "${SNAPSHOT_DIR}/baseline.sha256"
  
  log "✓ Baseline snapshot created: $(du -h ${SNAPSHOT_DIR}/baseline.tar.zst | cut -f1)"
}

# Setup per-job overlay (CoW mount)
setup_job_workspace() {
  log "🔧 Setting up ephemeral workspace for job: $JOB_ID"
  
  mkdir -p "$JOB_OVERLAY"/{upper,work}
  mkdir -p "${WORKSPACE_ROOT}"
  
  # Verify work directory doesn't exist or is empty
  if [ -d "${WORKSPACE_ROOT}/_job" ] && [ "$(ls -A ${WORKSPACE_ROOT}/_job 2>/dev/null)" ]; then
    error "Previous job workspace not cleaned: ${WORKSPACE_ROOT}/_job"
  fi
  
  # Create overlay mount (CoW filesystem)
  log "  → Creating overlay mount..."
  mount -t overlay overlay \
    -o lowerdir="${SNAPSHOT_DIR}/baseline",upperdir="${JOB_OVERLAY}/upper",workdir="${JOB_OVERLAY}/work" \
    "${WORKSPACE_ROOT}" 2>/dev/null || {
    
    # Fallback: if overlay not available, use bind mount
    log "  ⚠️  Overlay not available, using bind mount (CoW disabled)"
    mount --bind "${SNAPSHOT_DIR}/baseline" "${WORKSPACE_ROOT}"
  }
  
  # Record job metadata for this run
  cat > "${JOB_OVERLAY}/metadata.json" <<EOF
{
  "job_id": "$JOB_ID",
  "created_at": "$(date -Iseconds)",
  "pid": $$,
  "runner_version": "$(cat /etc/runner-image-metadata.json | jq -r .version)",
  "baseline_hash": "$(cat ${SNAPSHOT_DIR}/baseline.sha256 | cut -d' ' -f1)"
}
EOF
  
  log "✅ Workspace ready: $WORKSPACE_ROOT"
  log "   Overlay: $JOB_OVERLAY"
}

# Transactional cleanup with verification
cleanup_job_workspace() {
  local exit_code="$?"
  
  log "🧹 Starting transactional cleanup for job: $JOB_ID (exit code: $exit_code)"
  
  # Step 1: Terminate orphan processes
  log "  → Checking for orphan processes..."
  local orphans=$(lsof "$JOB_OVERLAY" 2>/dev/null | grep -v COMMAND | wc -l)
  
  if [ "$orphans" -gt 0 ]; then
    log "  ⚠️  Found $orphans processes holding files in job overlay"
    fuser -9 "$JOB_OVERLAY" 2>/dev/null || true
    sleep 1
  fi
  
  # Step 2: Unmount overlay
  log "  → Unmounting overlay filesystem..."
  if mountpoint -q "$WORKSPACE_ROOT"; then
    umount "$WORKSPACE_ROOT" 2>/dev/null || umount -l "$WORKSPACE_ROOT" 2>/dev/null || {
      error "Failed to unmount workspace: $WORKSPACE_ROOT"
    }
  fi
  
  # Step 3: Collect failure artifacts before purge
  if [ $exit_code -ne 0 ]; then
    log "  → Job failed, collecting artifacts for debugging..."
    
    local size_mb=$(du -sm "$JOB_OVERLAY/upper" 2>/dev/null | cut -f1 || echo 0)
    
    # Only archive if size > 10MB (to avoid noise)
    if [ "$size_mb" -gt 10 ]; then
      local archive_dir="/var/log/job-failures"
      mkdir -p "$archive_dir"
      
      tar -czf "${archive_dir}/job-${JOB_ID}-$(date +%s).tar.gz" \
        "$JOB_OVERLAY/upper" 2>/dev/null || true
      
      log "  ✓ Failure artifacts archived: ${archive_dir}/job-${JOB_ID}-*.tar.gz"
    fi
  fi
  
  # Step 4: Atomic purge with verification
  log "  → Purging job workspace..."
  if [ -x "$SAFE_DELETE" ]; then
    "$SAFE_DELETE" --path "$JOB_OVERLAY" --confirm --no-dry-run || error "Failed to remove overlay directory"
  else
    rm -rf "$JOB_OVERLAY" 2>/dev/null || error "Failed to remove overlay directory"
  fi
  
  # Verify cleanup
  if [ -d "$JOB_OVERLAY" ]; then
    error "Cleanup failed: $JOB_OVERLAY still exists"
  fi
  
  log "✅ Cleanup complete: $JOB_ID"
  log "   Exit code: $exit_code"
  log "   Workspace purged successfully"
  
  return $exit_code
}

# Main execution
main() {
  case "${1:-setup}" in
    setup)
      create_baseline_snapshot
      setup_job_workspace
      ;;
    cleanup)
      cleanup_job_workspace
      ;;
    *)
      echo "Usage: $0 {setup|cleanup}"
      exit 1
      ;;
  esac
}

# Register cleanup trap
trap cleanup_job_workspace EXIT

main "$@"
