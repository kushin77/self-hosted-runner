#!/usr/bin/env bash
set -euo pipefail

# Idempotent provisioning script for an approved fullstack host.
# Installs Docker, the Docker Compose plugin, and lightweight helpers (gcloud/vault instructions).
# Designed to be safe: checks before installing and does not overwrite existing configs.

REQUIRED_USER=${1:-deploy}

info(){ echo "[INFO] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERROR] $*" >&2; exit 1; }

if [[ $(id -u) -ne 0 ]]; then
  warn "This script should be run as root (sudo). Re-run with sudo or as root."
  exit 2
fi

info "Provisioning fullstack host for Phase 6 quickstart"

# Create deploy user if missing
if id -u "$REQUIRED_USER" >/dev/null 2>&1; then
  info "User '$REQUIRED_USER' already exists"
else
  info "Creating user '$REQUIRED_USER'"
  useradd -m -s /bin/bash -G docker "$REQUIRED_USER"
  passwd -l "$REQUIRED_USER" || true
fi

# Install Docker (Debian/Ubuntu path)
if command -v docker >/dev/null 2>&1; then
  info "Docker already installed"
else
  info "Installing Docker Engine (apt)"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker || true
fi

# Add deploy user to docker group
if id -nG "$REQUIRED_USER" | grep -qw docker; then
  info "User '$REQUIRED_USER' already in 'docker' group"
else
  info "Adding '$REQUIRED_USER' to 'docker' group"
  usermod -aG docker "$REQUIRED_USER"
fi

# Install Vault / gcloud notes (do not auto-authenticate) — provide CLI install instructions if missing
if command -v vault >/dev/null 2>&1; then
  info "Vault CLI present"
else
  info "Vault CLI not found; installing hashicorp vault (deb)
  "
  apt-get install -y unzip
  VAULT_VER="1.16.0"
  curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VER}/vault_${VAULT_VER}_linux_amd64.zip" -o /tmp/vault.zip
  unzip -o /tmp/vault.zip -d /usr/local/bin
  chmod +x /usr/local/bin/vault || true
fi

if command -v gcloud >/dev/null 2>&1; then
  info "gcloud CLI present"
else
  info "gcloud CLI missing — installation requires interactive steps. See FULLSTACK_PROVISIONING.md for guidance."
fi

# Deploy systemd service unit template for phase6 quickstart (copy only, do not enable)
TARGET_UNIT_DIR="/etc/systemd/system"
if [[ -f /etc/systemd/system/phase6-quickstart@.service ]]; then
  info "systemd unit template already present"
else
  info "Installing systemd unit template for phase6-quickstart (will not be enabled automatically)"
  cat > /etc/systemd/system/phase6-quickstart@.service <<'UNIT'
[Unit]
Description=Phase6 Quickstart Runner (%i)
After=network.target

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i/self-hosted-runner
ExecStart=/home/%i/self-hosted-runner/scripts/phase6-quickstart.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload || true
fi

info "Provisioning complete. Please ensure the following manual steps are completed as the deployment user ($REQUIRED_USER):"
cat <<EOF
- Add your SSH public key to /home/$REQUIRED_USER/.ssh/authorized_keys (owner: $REQUIRED_USER, mode 600)
- Authenticate gcloud: 'gcloud auth login' or configure a service account
- Authenticate Vault: set VAULT_ADDR and login method (token/approle)
- Place repository at /home/$REQUIRED_USER/self-hosted-runner (git clone or pull)
- Start the quickstart unit: 'sudo systemctl start phase6-quickstart@$REQUIRED_USER'
EOF

info "If you want, run the remote-runner from your local workstation to trigger the quickstart: export FULLSTACK_USER='$REQUIRED_USER' && export FULLSTACK_HOST=your.host && bash scripts/phase6-remote-runner.sh"

exit 0
