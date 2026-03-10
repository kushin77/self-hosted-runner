#!/usr/bin/env bash
set -euo pipefail

# Local runner for Phase 3B provisioning - replaces GitHub Actions
# - Reads credentials from environment / Vault
# - Runs existing provisioning script: scripts/phase3b-credentials-aws-vault.sh
# - Appends an immutable JSONL audit entry to logs/deployment-provisioning-audit.jsonl

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/phase3b-credentials-aws-vault.sh"
LOGDIR="$REPO_ROOT/logs"
AUDIT_FILE="$LOGDIR/deployment-provisioning-audit.jsonl"
RUN_LOG="$LOGDIR/deployment-provisioning-$(date -u +%Y%m%dT%H%M%SZ).log"

mkdir -p "$LOGDIR"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Minimal environment checks (do not expose secrets)
: "${VAULT_ADDR:?set VAULT_ADDR in environment or export via .env file}" || true

# If a Vault token file is present (vault-agent sink), export it for the duration of the run.
# This keeps tokens out of repo secrets and process args.
if [[ -z "${VAULT_TOKEN:-}" ]]; then
  if [[ -f "${VAULT_TOKEN_MOUNT_PATH:-}" ]]; then
    export VAULT_TOKEN=$(cat "$VAULT_TOKEN_MOUNT_PATH" | tr -d '\n' || true)
  elif [[ -n "${VAULT_TOKEN_FILE:-}" && -f "${VAULT_TOKEN_FILE}" ]]; then
    export VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE" | tr -d '\n' || true)
  fi
fi

# Run provisioning, capture output
{
  echo "[${timestamp()}] Phase3B runner starting"
  echo "Running: $SCRIPT"
  bash "$SCRIPT"
} >"$RUN_LOG" 2>&1 || {
  rc=$?
  # Write audit failure entry
  jq -n --arg ts "$(timestamp)" --arg ev "phase3b_run" --arg st "FAILURE" --arg file "$RUN_LOG" '{timestamp:$ts,event:$ev,status:$st,run_log:$file}' >> "$AUDIT_FILE" || true
  echo "Phase3B runner failed (rc=$rc). Log: $RUN_LOG"
  exit $rc
}

# On success, append audit entry
jq -n --arg ts "$(timestamp)" --arg ev "phase3b_run" --arg st "SUCCESS" --arg file "$RUN_LOG" '{timestamp:$ts,event:$ev,status:$st,run_log:$file}' >> "$AUDIT_FILE" || true

echo "Phase3B runner completed successfully. Log: $RUN_LOG"
exit 0
