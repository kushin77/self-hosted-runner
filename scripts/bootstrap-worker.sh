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
  install_systemd
  fix_permissions
  print_next_steps
  log "Bootstrap finished"
}

main "$@"
