#!/usr/bin/env bash
set -euo pipefail

# notify_on_failure.sh
# Usage: notify_on_failure.sh <status> <logfile>
# If INCIDENT_WEBHOOK is set, POSTs a JSON payload with status and tail of logfile.

STATUS=${1:-unknown}
LOGFILE=${2:-}

# If INCIDENT_WEBHOOK not provided, try to read from Google Secret Manager
if [ -z "${INCIDENT_WEBHOOK-}" ]; then
  if command -v gcloud >/dev/null 2>&1; then
    SECRET_NAME="incidents-webhook"
    PROJECT="nexusshield-prod"
    WEBHOOK_VAL=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" 2>/dev/null || true)
    if [ -n "$WEBHOOK_VAL" ]; then
      INCIDENT_WEBHOOK="$WEBHOOK_VAL"
    fi
  fi
fi

TAIL=$(if [ -n "$LOGFILE" ] && [ -f "$LOGFILE" ]; then tail -n 200 "$LOGFILE" | sed -e 's/"/\\"/g' -e 's/$/\\n/' | tr -d '\r' ; else "(no logfile)"; fi)

if [ -n "${INCIDENT_WEBHOOK-}" ]; then
  payload=$(cat <<EOF
{"status":"$STATUS","host":"$(hostname -f || hostname)","log":"$TAIL"}
EOF
)
  curl -fsS -X POST -H "Content-Type: application/json" -d "$payload" "$INCIDENT_WEBHOOK" || true
else
  echo "[notify] INCIDENT_WEBHOOK not set and no GSM secret found - printing summary:"
  echo "Status: $STATUS"
  echo "Log tail:" 
  echo "$TAIL"
fi
