#!/bin/bash
# automated_test_alert.sh
# Sends a test alert to Alertmanager (v2 API) to verify the monitoring pipeline.

set -euo pipefail

# Alertmanager URL (on node .42). Can be overridden with env var AM_URL.
AM_URL="${AM_URL:-http://192.168.168.42:9093}"

echo "Pushing synthetic alert to Alertmanager at ${AM_URL} (v2 API)..."

payload='[
  {
    "labels": {
      "alertname": "TestManualAlert",
      "instance": "manual-test",
      "severity": "critical",
      "service": "runner-health"
    },
    "annotations": {
      "summary": "Manual Test Alert for Slack Integration",
      "description": "Synthetic alert to verify Slack webhook via Alertmanager v2 API."
    }
  }
]'

# Try the Alertmanager v2 endpoint first
tmpfile=$(mktemp)
status=$(curl -sS -o "$tmpfile" -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "$payload" "${AM_URL}/api/v2/alerts" || true)

if [[ "$status" == "200" || "$status" == "202" || "$status" == "204" ]]; then
  echo "Alertmanager accepted the alert (status ${status})."
  cat "$tmpfile" || true
  rm -f "$tmpfile"
  echo -e "\nAlert pushed via v2 API. Please check the Slack channel configured in Alertmanager."
  exit 0
else
  echo "Alertmanager v2 endpoint returned HTTP ${status}. Response:" >&2
  cat "$tmpfile" >&2 || true
  rm -f "$tmpfile"
fi

# If v2 failed, fallback: if operator exported TEST_SLACK_WEBHOOK, send directly to Slack (useful for network-isolated environments).
if [[ -n "${TEST_SLACK_WEBHOOK:-}" ]]; then
  echo "Falling back to direct Slack POST using TEST_SLACK_WEBHOOK (env)."
  slack_payload='{"text":"[ALERT TEST] This is a direct test message from automated_test_alert.sh"}'
  curl -sS -X POST -H 'Content-type: application/json' --data "$slack_payload" "${TEST_SLACK_WEBHOOK}" && echo "Direct Slack POST sent." || echo "Direct Slack POST failed." >&2
  exit 0
fi

echo "Neither Alertmanager v2 accepted the alert nor TEST_SLACK_WEBHOOK is set. Please ensure Alertmanager is reachable and your Slack webhook is stored in Vault (see Issue #812)."
exit 2
