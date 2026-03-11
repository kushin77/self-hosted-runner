#!/bin/bash
# Cron setup: Auto-deploy synthetic health-check when credentials become available
# Install with: bash infra/terraform/tmp_observability/setup-credential-detector-cron.sh

set -euo pipefail

SCRIPT_PATH="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )/credential-detector.sh"
CRON_ENTRY="*/5 * * * * bash $SCRIPT_PATH >> /dev/null 2>&1"

if ! crontab -l 2>/dev/null | grep -q "credential-detector.sh"; then
    echo "Installing credential detector to crontab (every 5 min)..."
    (crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab -
    echo "✓ Cron job installed"
    crontab -l | grep credential-detector || echo "⚠ Verify: crontab -l | grep credential-detector"
else
    echo "✓ Credential detector already installed in crontab"
fi
