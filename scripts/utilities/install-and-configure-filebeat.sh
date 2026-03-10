#!/usr/bin/env bash
set -euo pipefail

# Install Filebeat 8.x on Ubuntu/Debian and deploy configuration
# Usage: ./scripts/install-and-configure-filebeat.sh [worker_host]
WORKER_HOST="${1:-akushnir@192.168.168.42}"
REMOTE_CONF="/etc/filebeat/filebeat.yml"
REMOTE_DIR="/etc/filebeat"

echo "Installing Filebeat on $WORKER_HOST"
ssh "$WORKER_HOST" bash -s <<'EOF'
set -euo pipefail

if command -v filebeat >/dev/null 2>&1; then
  echo "filebeat already installed"
else
  echo "Adding Elastic apt repo"
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  sudo apt-get install -y apt-transport-https ca-certificates
  echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
  sudo apt-get update
  sudo apt-get install -y filebeat
fi

sudo systemctl stop filebeat || true
sudo mkdir -p $REMOTE_DIR
sudo chown root:root $REMOTE_DIR
EOF

# Deploy config (reuse configure-filebeat script behavior)
./scripts/configure-filebeat.sh "$WORKER_HOST"

exit 0
