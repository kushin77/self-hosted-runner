#!/bin/bash
set -euo pipefail

# Provision common agents on a Debian/Ubuntu worker:
# - HashiCorp Vault Agent (config placeholder)
# - Filebeat (Elastic) for log shipping (or Datadog agent if DATADOG_API_KEY provided)
# - Prometheus node_exporter
# Usage: sudo bash worker-provision-agents.sh

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (or via sudo)" >&2
  exit 1
fi

log "Updating apt cache"
apt-get update -y

log "Installing prerequisites"
apt-get install -y curl unzip gnupg ca-certificates

# Install Vault (binary install)
if ! command -v vault >/dev/null 2>&1; then
  VAULT_VER="1.16.0"
  log "Installing HashiCorp Vault $VAULT_VER"
  curl -fsSL https://releases.hashicorp.com/vault/${VAULT_VER}/vault_${VAULT_VER}_linux_amd64.zip -o /tmp/vault.zip
  unzip -o /tmp/vault.zip -d /usr/local/bin && rm -f /tmp/vault.zip
  useradd --system --home /var/lib/vault --shell /usr/sbin/nologin vault || true
fi

# Create a simple vault-agent systemd unit and config placeholder
mkdir -p /etc/vault /etc/vault/agent.d /etc/systemd/system
cat >/etc/vault/agent.d/agent.hcl <<'EOF'
pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "approle" {}
}

sink "file" {
  path = "/etc/vault/agent-token"
}
EOF

cat >/etc/systemd/system/vault-agent.service <<'EOF'
[Unit]
Description=Vault Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vault agent -config=/etc/vault/agent.d/agent.hcl
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload || true
systemctl enable --now vault-agent.service || true

# Install Filebeat (elastic) simple install via apt repo
if ! command -v filebeat >/dev/null 2>&1; then
  log "Installing Filebeat"
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
  echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" >/etc/apt/sources.list.d/elastic-8.x.list
  apt-get update -y
  apt-get install -y filebeat
  systemctl enable --now filebeat || true
fi

# Install Prometheus node_exporter
if ! id -u node_exporter >/dev/null 2>&1; then
  useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true
fi
if [ ! -f /usr/local/bin/node_exporter ]; then
  NODE_VER="1.5.0"
  curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v${NODE_VER}/node_exporter-${NODE_VER}.linux-amd64.tar.gz -o /tmp/node_exporter.tar.gz
  tar -xzf /tmp/node_exporter.tar.gz -C /tmp
  install -m 0755 /tmp/node_exporter-${NODE_VER}.linux-amd64/node_exporter /usr/local/bin/node_exporter
  rm -rf /tmp/node_exporter* 
  cat >/etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=default.target
EOF
  systemctl daemon-reload || true
  systemctl enable --now node_exporter.service || true
fi

log "Provisioning complete. Configure Vault AppRole and Filebeat outputs as needed."
exit 0
