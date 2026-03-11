#!/usr/bin/env bash
set -euo pipefail

# Install a user crontab entry to run cross-backend validation hourly
CRON_CMD="cd $(pwd) && ./scripts/security/cross-backend-validator.sh --validate-all || ./scripts/ops/notify-validator-failure.sh 'Cross-backend validation failed at $(date -u)'"
# Write crontab
( crontab -l 2>/dev/null | grep -v -F "$CRON_CMD" || true ; echo "0 * * * * $CRON_CMD" ) | crontab -

echo "Installed hourly validator cron job."
