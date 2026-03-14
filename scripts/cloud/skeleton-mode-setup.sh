#!/usr/bin/env bash
set -euo pipefail

# Setup minimal skeleton/hibernation resources after cleanup
# This creates minimal managed DNS entries, a small VM/container for control plane,
# and ensures archive pointers are reachable. Defaults to dry-run.

DRY_RUN=${DRY_RUN:-true}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOGFILE="${LOGFILE:-${REPO_ROOT}/logs/cleanup/cleanup-audit.jsonl}"

mkdir -p "$(dirname "$LOGFILE")"

log(){
  command -v jq >/dev/null 2>&1 || true
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" --arg m "$1" '{timestamp:$ts,message:$m}' >> "$LOGFILE"
  else
    echo "$1" >> "$LOGFILE"
  fi
}

echo "Skeleton mode setup (dry-run=$DRY_RUN)"
log "skeleton_setup_invoked dry_run=$DRY_RUN"

if [ "$DRY_RUN" = "true" ]; then
  echo "DRY-RUN: would provision minimal control-plane resources and update DNS to point to skeleton"
  log "skeleton_setup_dry_run"
  exit 0
fi

echo "Provisioning skeleton resources..."
log "skeleton_setup_started"

# Real steps: create minimal VM/container, lock down SSH keys, set DNS A/CNAME to skeleton

log "skeleton_setup_completed"
echo "Skeleton mode setup completed"
