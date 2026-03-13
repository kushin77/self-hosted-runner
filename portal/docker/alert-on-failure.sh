#!/usr/bin/env bash
set -euo pipefail

# alert-on-failure.sh
# Sends a POST to ALERT_WEBHOOK if set. Fallback: write to syslog.

MESSAGE=${1:-"Service failure on $(hostname)"}

if [[ -n "${ALERT_WEBHOOK:-}" ]]; then
  curl -fsS -X POST -H 'Content-Type: application/json' -d "{\"text\": \"${MESSAGE}\"}" "$ALERT_WEBHOOK" || true
else
  logger -t portal-smoke-check "${MESSAGE}"
fi
