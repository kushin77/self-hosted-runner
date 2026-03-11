#!/usr/bin/env bash
set -euo pipefail

# Idempotent operator helper to revoke a user-managed SA key and delete a GSM secret.
# Run this from a privileged operator environment (has iam.serviceAccountKeys.delete).
#
# Usage:
# PROJECT=nexusshield-prod SA_EMAIL=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com \
# KEY_ID=a3b789c73d46e0265909216f14f7c22cea73ca66 SECRET_NAME=nxs-automation-sa-key \
# ./scripts/auth/revoke-fallback-key.sh

PROJECT="${PROJECT:-nexusshield-prod}"
SA_EMAIL="${SA_EMAIL:-nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com}"
KEY_ID="${KEY_ID:-a3b789c73d46e0265909216f14f7c22cea73ca66}"
SECRET_NAME="${SECRET_NAME:-nxs-automation-sa-key}"
AUDIT_FILE="artifacts/audit/credential-rotation-20260311-revoke-final.jsonl"

echo "Starting revoke helper (project=$PROJECT, sa=$SA_EMAIL, key=$KEY_ID, secret=$SECRET_NAME)"

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log_audit() {
  local evt="$1"; local note="$2";
  mkdir -p "$(dirname "$AUDIT_FILE")"
  printf '%s' "{\"timestamp\":\"$(timestamp)\",\"event\":\"$evt\",\"service_account\":\"$SA_EMAIL\",\"key_id\":\"$KEY_ID\",\"note\":\"$note\"}\n" >> "$AUDIT_FILE"
}

# Check key existence
if ! gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$PROJECT" --format=json | jq -e ".[] | select(.name | contains(\"$KEY_ID\"))" >/dev/null 2>&1; then
  echo "Key $KEY_ID not found for $SA_EMAIL (already removed)"
  log_audit "REVOKE_FALLBACK_KEY_SKIPPED" "key_not_found_or_already_deleted"
  exit 0
fi

echo "Attempting to delete service account key $KEY_ID..."
if gcloud iam service-accounts keys delete "$KEY_ID" --iam-account="$SA_EMAIL" --project="$PROJECT" --quiet; then
  echo "Deleted SA key $KEY_ID"
  log_audit "REVOKE_FALLBACK_KEY_SUCCESS" "key_deleted"
else
  echo "Failed to delete SA key $KEY_ID (insufficient permissions or other error)" >&2
  log_audit "REVOKE_FALLBACK_KEY_FAILED" "key_delete_failed"
  exit 2
fi

echo "Attempting to delete GSM secret $SECRET_NAME (if exists)..."
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  if gcloud secrets delete "$SECRET_NAME" --project="$PROJECT" --quiet; then
    echo "Deleted secret $SECRET_NAME"
    log_audit "DELETE_GSM_SECRET_SUCCESS" "secret_deleted"
  else
    echo "Failed to delete secret $SECRET_NAME" >&2
    log_audit "DELETE_GSM_SECRET_FAILED" "secret_delete_failed"
  fi
else
  echo "Secret $SECRET_NAME not found; nothing to delete"
  log_audit "DELETE_GSM_SECRET_SKIPPED" "secret_not_found"
fi

echo "Revoke helper completed. Audit appended to $AUDIT_FILE"
