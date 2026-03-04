#!/usr/bin/env bash
set -euo pipefail

# install-watchdog-remote.sh
# Copies systemd user unit and timer to remote user's systemd user directory
# and enables the timer. Requires SSH access to remote host as the same user.

REMOTE_HOST="192.168.168.42"
REMOTE_USER="akushnir"
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/systemd"

echo "Uploading systemd user units to ${REMOTE_USER}@${REMOTE_HOST}"

ssh ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ~/.config/systemd/user"

for f in runner-watchdog.service runner-watchdog.timer; do
  echo "Uploading: $f"
  base64 -w0 "${LOCAL_DIR}/$f" | ssh ${REMOTE_USER}@${REMOTE_HOST} "base64 -d > ~/.config/systemd/user/$f && chmod 644 ~/.config/systemd/user/$f"
done

# Optional: upload environment file containing WATCHDOG_WEBHOOK_URL (do not commit secrets)
if [[ -n "${1:-}" && -f "$1" ]]; then
  echo "Uploading environment file: $1"
  base64 -w0 "$1" | ssh ${REMOTE_USER}@${REMOTE_HOST} "base64 -d > ~/.config/systemd/user/runner-watchdog.env && chmod 600 ~/.config/systemd/user/runner-watchdog.env"
  echo "Uploaded runner-watchdog.env to remote user config"
fi

echo "Reloading systemd user daemon on remote"
ssh ${REMOTE_USER}@${REMOTE_HOST} "systemctl --user daemon-reload || true"

echo "Enabling and starting timer"
ssh ${REMOTE_USER}@${REMOTE_HOST} "systemctl --user enable --now runner-watchdog.timer || true"

echo "Check status: systemctl --user status runner-watchdog.timer && systemctl --user list-timers --all | grep runner-watchdog"
ssh ${REMOTE_USER}@${REMOTE_HOST} "systemctl --user status runner-watchdog.timer --no-pager || true; systemctl --user list-timers --all | grep runner-watchdog || true"

echo "If you want the service to persist across reboots for this user, enable linger on the host: sudo loginctl enable-linger ${REMOTE_USER} (requires sudo)."

echo "Done"
