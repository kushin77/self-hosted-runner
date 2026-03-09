#!/usr/bin/env bash
set -euo pipefail

# Bootstrap worker node for direct-deploy model
# Idempotent: can be run multiple times safely

REPO_DIR="/opt/self-hosted-runner"
SERVICE_SRC="$(dirname "${BASH_SOURCE[0]}")/../infra/wait-and-deploy.service"
SERVICE_DST="/etc/systemd/system/wait-and-deploy.service"

log(){ echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }

ensure_user(){
  if id -u deploy >/dev/null 2>&1; then
    log "user 'deploy' exists"
  else
    log "creating user 'deploy'"
    sudo useradd -m -s /bin/bash deploy || true
  fi
}

ensure_dirs(){
  sudo mkdir -p "$REPO_DIR"
  sudo chown deploy:deploy "$REPO_DIR"
  sudo mkdir -p "$REPO_DIR/logs"
  sudo chown deploy:deploy "$REPO_DIR/logs"
}

install_systemd(){
  if [ -f "$SERVICE_SRC" ]; then
    log "Installing systemd service from $SERVICE_SRC"
    sudo cp "$SERVICE_SRC" "$SERVICE_DST"
    sudo chown root:root "$SERVICE_DST"
    sudo chmod 644 "$SERVICE_DST"
    sudo systemctl daemon-reload || true
    sudo systemctl enable --now wait-and-deploy.service || true
    log "Systemd service enabled: wait-and-deploy.service"
  else
    log "Service source not found: $SERVICE_SRC — skipping systemd install"
  fi
}

install_vault_agent(){
  if command -v vault >/dev/null 2>&1; then
    log "vault binary already installed"
  else
    log "Installing Vault CLI/Agent (HashiCorp release)..."
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    VER=${VAULT_VERSION:-1.16.0}
    OS=$(uname | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then ARCH=amd64; fi
    URL="https://releases.hashicorp.com/vault/${VER}/vault_${VER}_${OS}_${ARCH}.zip"
    if curl -fsSLO "$URL"; then
      unzip -q "vault_${VER}_${OS}_${ARCH}.zip"
      sudo mv vault /usr/local/bin/
      sudo chmod 755 /usr/local/bin/vault
      log "vault installed to /usr/local/bin/vault"
    else
      log "Failed to download Vault from $URL — skipping install"
    fi
    cd - >/dev/null || true
    rm -rf "$tmpdir"
  fi

  # Install agent config and template
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/../config/vault-agent.hcl" ]; then
    sudo mkdir -p /etc/vault/templates
    sudo cp "$(dirname "${BASH_SOURCE[0]}")/../config/vault-agent.hcl" /etc/vault/agent.hcl
    sudo cp "$(dirname "${BASH_SOURCE[0]}")/../config/deployment.env.tpl" /etc/vault/templates/deployment.env.tpl
    sudo chown -R root:root /etc/vault
    sudo chmod 644 /etc/vault/agent.hcl || true
    log "Vault Agent configuration installed to /etc/vault"
  else
    log "No Vault Agent config found in repo; skipping config deploy"
  fi

  # Install systemd unit for vault-agent if present in repo infra
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/../infra/vault-agent.service" ]; then
    sudo cp "$(dirname "${BASH_SOURCE[0]}")/../infra/vault-agent.service" /etc/systemd/system/vault-agent.service
    sudo chown root:root /etc/systemd/system/vault-agent.service
    sudo chmod 644 /etc/systemd/system/vault-agent.service
    sudo systemctl daemon-reload || true
    sudo systemctl enable --now vault-agent.service || true
    log "vault-agent systemd enabled and started"
  else
    log "vault-agent.service file missing in repo infra; skipping service install"
  fi
}

install_dependencies(){
  # Install minimal tooling if available via package manager
  if command -v apt-get >/dev/null 2>&1; then
    PKG_OK=$(dpkg -s jq 2>/dev/null || true)
    sudo apt-get update -y || true
    sudo apt-get install -y jq curl git ca-certificates || true
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y jq curl git ca-certificates || true
  else
    log "No supported package manager found (apt/yum). Ensure jq/curl/git are installed manually."
  fi
}

fix_permissions(){
  sudo find "$REPO_DIR" -type d -exec chmod 755 {} + || true
  sudo chown -R deploy:deploy "$REPO_DIR" || true
}

print_next_steps(){
  cat <<EOF
Bootstrap complete. Next manual steps for operator:

- Ensure credential providers are configured (GSM/Vault/KMS) for runner keys and deployment fields.
- Populate environment on worker or provide secrets to GSM/Vault/KMS.
- Verify service status: sudo systemctl status wait-and-deploy.service
- To run watcher manually: sudo -u deploy bash $REPO_DIR/scripts/wait-and-deploy.sh gsm

Audit: the worker will write provisioning events to $REPO_DIR/logs/deployment-provisioning-audit.jsonl
EOF
}

main(){
  log "Bootstrapping worker node"
  ensure_user
  ensure_dirs
  install_dependencies
  install_vault_agent
  install_systemd
  fix_permissions
  print_next_steps
  log "Bootstrap finished"
}

main "$@"
