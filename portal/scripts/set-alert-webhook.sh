#!/usr/bin/env bash
set -euo pipefail

# Usage: ./set-alert-webhook.sh user@worker "https://hooks.example/..."
# Installs a systemd drop-in for smoke-check.service setting ALERT_WEBHOOK

REMOTE=${1:-}
WEBHOOK=${2:-}

if [[ -z "$REMOTE" || -z "$WEBHOOK" ]]; then
  echo "Usage: $0 user@worker \"https://webhook.url/...\"" >&2
  exit 1
fi

echo "Installing ALERT_WEBHOOK on $REMOTE"

ssh "$REMOTE" bash -s <<SSH
set -euo pipefail
WORKDIR=~/self-hosted-runner/portal/docker
cd "\$WORKDIR"
DROP_DIR=/etc/systemd/system/smoke-check.service.d
sudo mkdir -p "\$DROP_DIR"
sudo tee "\$DROP_DIR/override.conf" > /dev/null <<EOF
[Service]
Environment=\"ALERT_WEBHOOK=${WEBHOOK}\"
Environment=\"ALERT_THRESHOLD=2\"
Environment=\"ALERT_COOLDOWN_SECONDS=1800\"
EOF

sudo systemctl daemon-reload
sudo systemctl restart smoke-check.timer || sudo systemctl start smoke-check.timer
sudo systemctl status smoke-check.timer --no-pager --full
echo "ALERT_WEBHOOK installed on $(hostname)"
SSH

echo "Done."
