#!/usr/bin/env bash
set -euo pipefail

# Installs the systemd user timer and enables it. Falls back to printing
# instructions if `systemctl --user` is unavailable.

UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"

cp -v "$PWD/scripts/verify/smoke_check.service" "$UNIT_DIR/smoke_check.service"
cp -v "$PWD/scripts/verify/smoke_check.timer" "$UNIT_DIR/smoke_check.timer"
chmod 644 "$UNIT_DIR/smoke_check."*

if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1; then
  echo "Enabling and starting smoke_check.timer"
  systemctl --user enable --now smoke_check.timer
  systemctl --user status smoke_check.timer --no-pager
else
  cat <<EOF
Systemd user not available or command failed. To enable the timer manually:

mkdir -p ~/.config/systemd/user
cp scripts/verify/smoke_check.service ~/.config/systemd/user/
cp scripts/verify/smoke_check.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now smoke_check.timer

If running on a container or minimal host without systemd, use cron:

crontab -l 2>/dev/null | { cat; echo "0 * * * * $PWD/scripts/verify/smoke_check.sh >/tmp/smoke_check.log 2>&1"; } | crontab -

EOF
fi
