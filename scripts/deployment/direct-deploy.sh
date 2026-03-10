#!/usr/bin/env bash
set -euo pipefail

# Direct deploy wrapper — call existing repo deploy scripts safely
# Usage: scripts/direct-deploy.sh [environment]

ENV=${1:-production}
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_SCRIPT="$ROOT_DIR/nexusshield/scripts/deploy-production.sh"
LOG_DIR="$ROOT_DIR/logs"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_FILE="$LOG_DIR/direct-deploy-$ENV-$(date -u +%Y%m%d).jsonl"

mkdir -p "$LOG_DIR"

audit() {
  local status="$1"; shift
  local msg="$*"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg ts "$TIMESTAMP" --arg env "$ENV" --arg status "$status" --arg msg "$msg" '{timestamp:$ts,environment:$env,status:$status,message:$msg}' >> "$AUDIT_FILE"
  else
    printf '{"timestamp":"%s","environment":"%s","status":"%s","message":"%s"}\n' "$TIMESTAMP" "$ENV" "$status" "$msg" >> "$AUDIT_FILE"
  fi
}

if [ ! -x "$DEPLOY_SCRIPT" ]; then
  echo "Error: deploy script not found or not executable: $DEPLOY_SCRIPT" >&2
  audit "error" "deploy script missing"
  exit 2
fi

audit "started" "direct-deploy wrapper starting"
echo "Running direct deploy for environment: $ENV"

set +e
"$DEPLOY_SCRIPT" "$ENV"
RC=$?
set -e

if [ $RC -eq 0 ]; then
  audit "success" "deploy script exited 0"
  echo "Deploy completed successfully"
else
  audit "failed" "deploy script exited $RC"
  echo "Deploy failed with exit code $RC" >&2
fi

exit $RC
