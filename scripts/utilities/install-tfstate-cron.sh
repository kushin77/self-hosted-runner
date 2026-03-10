#!/usr/bin/env bash
set -euo pipefail

# Installs a cron entry to run the tfstate backup every 6 hours as the current user.
# Requires `gsutil` authenticated and access to the GCS bucket.

CRON_ENTRY="0 */6 * * * $(pwd)/scripts/backup_tfstate.sh >> $(pwd)/logs/backup_tfstate.log 2>&1"

# Ensure logs dir
mkdir -p logs

(crontab -l 2>/dev/null | grep -v -F "backup_tfstate.sh" || true; echo "$CRON_ENTRY") | crontab -

echo "Installed cron job to run every 6 hours. Check logs/backup_tfstate.log for output."
