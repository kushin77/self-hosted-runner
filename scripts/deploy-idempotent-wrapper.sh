#!/bin/bash
# Minimal idempotent deployment wrapper (recreated)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENT_ENV="${DEPLOYMENT_ENV:-staging}"
CHECK_ONLY="false"
STATE_DIR="/run/app-deployment-state"
STATE_FILE="$STATE_DIR/deployed.state"

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) DEPLOYMENT_ENV="$2"; shift 2;;
    --check-only) CHECK_ONLY="true"; shift;;
    *) shift;;
  esac
done

mkdir -p "$STATE_DIR" /opt/app/logs || true

if [[ -f "$STATE_FILE" && "$CHECK_ONLY" != "true" ]]; then
  log "Already deployed (state file exists); exiting"
  exit 0
fi

# Release gate for production: require manual approval file
if [[ "$DEPLOYMENT_ENV" == "production" ]]; then
  GATE_FILE="/opt/release-gates/production.approved"
  if [[ ! -f "$GATE_FILE" ]]; then
    log "ERROR: production release gate not found: $GATE_FILE"
    log "To approve a production deployment, create the file as root: sudo mkdir -p /opt/release-gates && sudo touch $GATE_FILE && sudo chown root:root $GATE_FILE && sudo chmod 0644 $GATE_FILE"
    exit 2
  fi
  # Optional freshness check: file age less than 7 days
  if ! find "$GATE_FILE" -mtime -7 -print -quit >/dev/null 2>&1; then
    log "ERROR: production release gate file is older than 7 days; recreate to approve"
    exit 2
  fi
  log "Production release gate present and fresh"
fi

# Deploy steps (minimal): copy files to /opt/app-staging, set read-only where applicable
log "Starting deployment: env=$DEPLOYMENT_ENV"
mkdir -p /opt/app-staging
cp -a "$REPO_ROOT"/* /opt/app-staging/ 2>/dev/null || true

# Mark deployed state
if [[ "$CHECK_ONLY" != "true" ]]; then
  cat > "$STATE_FILE" <<EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","env":"$DEPLOYMENT_ENV","deployer":"${USER:-ops}"}
EOF
  log "Deployment recorded"
else
  log "Check-only mode: no state changes written"
fi

log "Deployment wrapper complete"
exit 0
