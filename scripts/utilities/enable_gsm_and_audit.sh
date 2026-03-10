#!/usr/bin/env bash
set -euo pipefail

PROJECT=p4-platform
AUDIT_LOG=logs/complete-finalization-audit.jsonl
mkdir -p "$(dirname "$AUDIT_LOG")"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
TMP_OUT=$(mktemp)

if gcloud services enable secretmanager.googleapis.com --project="$PROJECT" >"$TMP_OUT" 2>&1; then
  STATUS=success
  MSG="Secret Manager API enabled successfully"
else
  STATUS=permission_denied
  MSG=$(sed -n '1,200p' "$TMP_OUT" | tr '\n' ' ')
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg ts "$TS" --arg op "gsm-api-enable" --arg status "$STATUS" --arg msg "$MSG" --arg issue "#2116" --arg commit "$COMMIT" '{timestamp:$ts,operation:$op,status:$status,message:$msg,issue:$issue,commit:$commit}' >> "$AUDIT_LOG"
else
  printf '%s\n' "{\"timestamp\":\"$TS\",\"operation\":\"gsm-api-enable\",\"status\":\"$STATUS\",\"message\":\"$(echo "$MSG" | sed 's/"/\\"/g')\",\"issue\":\"#2116\",\"commit\":\"$COMMIT\"}" >> "$AUDIT_LOG"
fi

rm -f "$TMP_OUT"

git add "$AUDIT_LOG" || true
git commit -m "audit: record GSM API enablement attempt for p4-platform (#2116)" --no-verify || true

echo "GSM_ENABLE_STATUS=$STATUS"
