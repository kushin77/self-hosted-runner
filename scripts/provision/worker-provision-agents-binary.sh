#!/bin/bash
set -euo pipefail

# Provision agents on worker using pre-built binaries (no apt dependency)
# Usage: sudo bash worker-provision-agents-binary.sh

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (or via sudo)" >&2
  exit 1
fi

log "=== Vault Agent Provisioning ==="
if ! command -v vault >/dev/null 2>&1; then
  VAULT_VER="1.16.0"
  log "Installing Vault $VAULT_VER"
  mkdir -p /tmp/vault-install
  cd /tmp/vault-install
  curl -sSLf https://releases.hashicorp.com/vault/${VAULT_VER}/vault_${VAULT_VER}_linux_amd64.zip -o vault.zip
  unzip -o vault.zip && mv vault /usr/local/bin/vault && chmod +x /usr/local/bin/vault
  cd - && rm -rf /tmp/vault-install
  log "Vault installed: $(vault version)"
else
  log "Vault already installed: $(vault version)"
fi

# Create vault user if needed
useradd --system --home /var/lib/vault --shell /usr/sbin/nologin vault 2>/dev/null || true

# Create vault config directory
mkdir -p /etc/vault/agent.d /var/lib/vault
chown -R vault:vault /var/lib/vault /etc/vault

# Create vault-agent config placeholder
cat > /etc/vault/agent.d/agent.hcl <<'EOF'
pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/etc/vault/approle-role-id"
      secret_id_file_path = "/etc/vault/approle-secret-id"
    }
  }
}

sink "file" {
  path = "/etc/vault/agent-token"
  owner = "vault"
  mode = 0640
}
EOF

# Create systemd unit
cat > /etc/systemd/system/vault-agent.service <<'EOF'
[Unit]
Description=Vault Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/vault agent -config=/etc/vault/agent.d/agent.hcl
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vault-agent
User=vault
Group=vault

[Install]
WantedBy=multi-user.target
EOF

log "Vault agent systemd unit created"

log "=== Prometheus Node Exporter Provisioning ==="
if ! command -v node_exporter >/dev/null 2>&1; then
  NODE_VER="1.5.0"
  log "Installing node_exporter $NODE_VER"
  mkdir -p /tmp/ne-install
  cd /tmp/ne-install
  curl -sSLf https://github.com/prometheus/node_exporter/releases/download/v${NODE_VER}/node_exporter-${NODE_VER}.linux-amd64.tar.gz -o ne.tar.gz
  tar xzf ne.tar.gz && install -m 0755 node_exporter-${NODE_VER}.linux-amd64/node_exporter /usr/local/bin/
  cd - && rm -rf /tmp/ne-install
  log "node_exporter installed: $(node_exporter --version | head -1)"
else
  log "node_exporter already installed: $(node_exporter --version | head -1)"
fi

# Create node_exporter user
useradd --no-create-home --shell /usr/sbin/nologin node_exporter 2>/dev/null || true

# Create systemd unit for node_exporter
cat > /etc/systemd/system/node_exporter.service <<'EOF'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.filesystem.mount-points-exclude=^/(dev|proc|sys)($|/) --collector.netdev.device-exclude=^(veth.*)$
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

log "node_exporter systemd unit created"

log "=== Audit Log Directory Setup ==="
mkdir -p /opt/release-gates /opt/app/logs /run/app-deployment-state
chmod 755 /opt/release-gates /opt/app/logs
log "Directories created"

log "=== Reloading systemd ==="
systemctl daemon-reload

log "=== Starting services ==="
systemctl enable vault-agent.service 2>/dev/null || true
systemctl enable node_exporter.service 2>/dev/null || true

# Try to start services (they may fail due to missing config; that's OK)
systemctl start vault-agent.service 2>/dev/null || log "vault-agent start deferred (needs AppRole config)"
systemctl start node_exporter.service || log "node_exporter failed to start"

log "=== Provisioning Summary ==="
log "Vault: $(command -v vault)"
log "node_exporter: $(command -v node_exporter)"
log "Services enabled: vault-agent, node_exporter"
log "Directories created: /opt/release-gates, /opt/app/logs, /run/app-deployment-state"
log "Portal: http://$(hostname -I | awk '{print $1}'):9100/metrics"
log ""
log "NEXT STEPS:"
log "1. Configure Vault AppRole:"
log "   - Place AppRole role_id in: /etc/vault/approle-role-id"
log "   - Place AppRole secret_id in: /etc/vault/approle-secret-id"
log "   - Restart: sudo systemctl restart vault-agent"
log "2. Verify node_exporter: curl http://localhost:9100/metrics"
log "3. Configure Prometheus to scrape: http://$(hostname -I | awk '{print $1}'):9100/metrics"
log ""
log "Provisioning complete!"
exit 0
