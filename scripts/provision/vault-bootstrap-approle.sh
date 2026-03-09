#!/bin/bash
set -euo pipefail

# Bootstrap Vault AppRole credentials for vault-agent on the worker
# Usage: ./vault-bootstrap-approle.sh <VAULT_ADDR> <ROLE_ID> <SECRET_ID>
# Example: ./vault-bootstrap-approle.sh https://vault.example.com:8200 my-role-id my-secret-id

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@"; }

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <VAULT_ADDR> <ROLE_ID> <SECRET_ID>" >&2
  echo "Example: $0 https://vault.dev.example.com:8200 my-role-id my-secret-id" >&2
  exit 1
fi

VAULT_ADDR="$1"
ROLE_ID="$2"
SECRET_ID="$3"

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (or via sudo)" >&2
  exit 1
fi

log "Configuring Vault AppRole for vault-agent"
log "VAULT_ADDR: $VAULT_ADDR"

# Write AppRole credentials
echo "$ROLE_ID" > /etc/vault/approle-role-id
echo "$SECRET_ID" > /etc/vault/approle-secret-id
chmod 0600 /etc/vault/approle-role-id /etc/vault/approle-secret-id
chown vault:vault /etc/vault/approle-role-id /etc/vault/approle-secret-id

# Update vault-agent config
cat > /etc/vault/agent.d/agent.hcl <<EOF
pid_file = "/var/run/vault-agent.pid"

vault {
  address = "$VAULT_ADDR"
}

# Disable TLS verification for self-signed certs (not recommended for production)
# To enable: pass -tls-skip-verify to vault agent, or set:
# tls {
#   ca_cert = "/path/to/ca.crt"
# }

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/etc/vault/approle-role-id"
      secret_id_file_path = "/etc/vault/approle-secret-id"
      remove_secret_id_file_after_reading = false
    }
  }
}

sink "file" {
  path = "/etc/vault/agent-token"
  owner = "vault"
  mode = 0640
}

template {
  source = "/etc/vault/templates/app-config.tpl"
  destination = "/opt/app/config.json"
  command = "systemctl restart app-service"
}
EOF

log "Vault agent config created and AppRole credentials installed"
log "Restarting vault-agent service..."
systemctl restart vault-agent
sleep 2

log "Checking vault-agent status..."
if systemctl is-active vault-agent >/dev/null; then
  log "✓ vault-agent is running"
  log "Token file: /etc/vault/agent-token"
  log "Next: Configure templates in /etc/vault/templates/ for application config injection"
else
  log "✗ vault-agent failed to start; check: sudo journalctl -u vault-agent -n 50"
  exit 1
fi

exit 0
