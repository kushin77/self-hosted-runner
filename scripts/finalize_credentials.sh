#!/bin/bash
# Idempotent helper to finalize GSM/Vault/KMS credential provisioning.
# Behavior:
# - Dry-run by default. Set `FINALIZE=1` to perform live actions.
# - Uses `gcloud` when available and environment variables to decide flows.
# - Appends actions to an append-only JSONL audit in `logs/`.

set -euo pipefail

WORKDIR=$(cd "$(dirname "$0")/.." && pwd)
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
audit() {
  local action="$1"; shift
  local status="$1"; shift
  local details="$*"
  printf '%s\n' "{\"timestamp\":\"$(timestamp)\",\"action\":\"$action\",\"status\":\"$status\",\"details\":\"$details\"}" >> "$LOGDIR/gcp-admin-provisioning-$(date -u +%Y%m%d).jsonl"
}

DRY_RUN=true
if [ "${FINALIZE:-0}" = "1" ]; then
  DRY_RUN=false
fi

echo "Running credential finalization (FINALIZE=${FINALIZE:-0})"

# Check for VAULT_ADDR
if [ -n "${VAULT_ADDR:-}" ]; then
  echo "Vault address configured: $VAULT_ADDR"
  audit "vault_connectivity" "PRESENT" "VAULT_ADDR set"
else
  echo "Vault address not configured (VAULT_ADDR empty). Vault provisioning will be skipped." >&2
  audit "vault_connectivity" "NOT_CONFIGURED" "VAULT_ADDR missing"
fi

# GSM secret creation if SA key provided via env (base64-encoded JSON expected in GSM_SA_KEY_B64)
if [ -n "${GSM_SECRET_NAME:-}" ] && [ -n "${GSM_SA_KEY_B64:-}" ]; then
  if $DRY_RUN; then
    echo "DRY-RUN: Would create/replace GSM secret $GSM_SECRET_NAME"
    audit "gsm_secret_create" "DRY_RUN" "Would create secret $GSM_SECRET_NAME"
  else
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "gcloud not found; cannot create GSM secret." >&2
      audit "gsm_secret_create" "FAILED" "gcloud not found"
      exit 1
    fi
    tmpfile=$(mktemp)
    echo "$GSM_SA_KEY_B64" | base64 -d > "$tmpfile"
    if gcloud secrets describe "$GSM_SECRET_NAME" >/dev/null 2>&1; then
      gcloud secrets versions add "$GSM_SECRET_NAME" --data-file="$tmpfile"
      audit "gsm_secret_create" "UPDATED" "$GSM_SECRET_NAME"
    else
      gcloud secrets create "$GSM_SECRET_NAME" --replication-policy="automatic"
      gcloud secrets versions add "$GSM_SECRET_NAME" --data-file="$tmpfile"
      audit "gsm_secret_create" "CREATED" "$GSM_SECRET_NAME"
    fi
    rm -f "$tmpfile"
  fi
else
  audit "gsm_secret_create" "SKIPPED" "GSM_SECRET_NAME or GSM_SA_KEY_B64 not provided"
fi

echo "Credential finalization helper finished. See logs/ for JSONL audit entries."
