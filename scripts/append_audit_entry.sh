#!/usr/bin/env bash
set -euo pipefail

# Usage: append_audit_entry.sh event_type details_json
# Example: append_audit_entry.sh deployment '{"status":"success","id":"deploy-123"}'

AUDIT_FILE="nexusshield/logs/deployment-audit.jsonl"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <event_type> [details_json]" >&2
  exit 2
fi

EVENT_TYPE="$1"
DETAILS="{}"
if [ "$#" -ge 2 ]; then
  DETAILS="$2"
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$(dirname "$AUDIT_FILE")"
printf '%s
'"{"timestamp":"$TS","event":"$EVENT_TYPE","details":$DETAILS}" >> "$AUDIT_FILE"

echo "Appended audit entry to $AUDIT_FILE"
