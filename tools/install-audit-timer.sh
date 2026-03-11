#!/usr/bin/env bash

# Installer for systemd timer that runs the audit aggregation daily.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_TPL="$REPO_ROOT/tools/systemd/audit-aggregate.service.tmpl"
TIMER_TPL="$REPO_ROOT/tools/systemd/audit-aggregate.timer.tmpl"
OUT_SERVICE="/etc/systemd/system/audit-aggregate.service"
OUT_TIMER="/etc/systemd/system/audit-aggregate.timer"

if [ "$EUID" -ne 0 ]; then
  echo "This installer requires root. Re-run with sudo: sudo $0"
  exit 1
fi

if [ ! -f "$SERVICE_TPL" ] || [ ! -f "$TIMER_TPL" ]; then
  echo "Templates missing in $REPO_ROOT/tools/systemd. Aborting."
  exit 2
fi

sed "s|{{REPO_ROOT}}|$REPO_ROOT|g" "$SERVICE_TPL" | tee "$OUT_SERVICE" >/dev/null
sed "s|{{REPO_ROOT}}|$REPO_ROOT|g" "$TIMER_TPL" | tee "$OUT_TIMER" >/dev/null

systemctl daemon-reload
systemctl enable --now audit-aggregate.timer

echo "Installed and enabled audit-aggregate.timer (runs daily)."
echo "To view status: systemctl status audit-aggregate.timer"

exit 0
