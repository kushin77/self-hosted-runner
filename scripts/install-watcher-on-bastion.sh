#!/usr/bin/env bash
set -euo pipefail

# install-watcher-on-bastion.sh
# Usage: ./scripts/install-watcher-on-bastion.sh <bastion-host> [user] [ssh-key]

HOST="${1:-}"
USER="${2:-ops}"
SSH_KEY="${3:-~/.ssh/deploy-key}"

if [ -z "$HOST" ]; then
  echo "Usage: $0 <bastion-host> [user] [ssh-key]"
  exit 2
fi

echo "Installing watcher on ${USER}@${HOST} using key ${SSH_KEY}"

REMOTE_BIN=/usr/local/bin/wait-and-deploy.sh
REMOTE_SERVICE=/etc/systemd/system/wait-and-deploy.service

scp -i "$SSH_KEY" scripts/wait-and-deploy.sh "${USER}@${HOST}:/tmp/wait-and-deploy.sh"
scp -i "$SSH_KEY" infra/wait-and-deploy.service "${USER}@${HOST}:/tmp/wait-and-deploy.service"

ssh -i "$SSH_KEY" "${USER}@${HOST}" /bin/bash <<'EOF'
set -euo pipefail
sudo mv /tmp/wait-and-deploy.sh /usr/local/bin/wait-and-deploy.sh
sudo chmod +x /usr/local/bin/wait-and-deploy.sh
sudo mv /tmp/wait-and-deploy.service /etc/systemd/system/wait-and-deploy.service
sudo systemctl daemon-reload
sudo systemctl enable --now wait-and-deploy.service
sudo systemctl status --no-pager wait-and-deploy.service
EOF

echo "Watcher installed and started on ${HOST} (check systemctl status for details)"
