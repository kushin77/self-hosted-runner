#!/usr/bin/env bash
set -euo pipefail

# Deploy the existing services/managed-auth service to the worker as the API on port 8080.
# Usage: ./deploy_managed_auth_as_api.sh [ssh_user] [workspace_path] [worker_host]
# If not provided, defaults: ssh_user=akushnir, workspace_path=/home/<user>/self-hosted-runner, worker_host from config/infrastructure-env.sh

SSH_USER=${1:-akushnir}
WORKSPACE_DIR=${2:-/home/${SSH_USER}/self-hosted-runner}

# try to source repo environment if available
if [ -f "config/infrastructure-env.sh" ]; then
  # shellcheck disable=SC1091
  source config/infrastructure-env.sh
fi

WORKER_HOST=${3:-${API_BACKEND_NODE:-192.168.168.42}}

REMOTE_SERVICE_DIR="${WORKSPACE_DIR}/services/managed-auth"
SERVICE_NAME=eiq-api

echo "Deploying managed-auth as ${SERVICE_NAME} to ${WORKER_HOST} as ${SSH_USER}@${WORKER_HOST}"

ssh -o BatchMode=yes ${SSH_USER}@${WORKER_HOST} bash -s <<EOF
set -euo pipefail
WORKSPACE_DIR="${WORKSPACE_DIR}"
SERVICE_NAME="${SERVICE_NAME}"

mkdir -p "${WORKSPACE_DIR}/services"
cd "${WORKSPACE_DIR}/services"

# If managed-auth source already exists, update it; otherwise try to copy from the repository path
if [ -d managed-auth ]; then
  echo "managed-auth already exists on host; pulling latest if git present"
  if [ -d managed-auth/.git ]; then
    (cd managed-auth && git pull --ff-only) || true
  fi
else
  echo "Copying managed-auth from repository workspace path"
  if [ -d /home/${SSH_USER}/self-hosted-runner/services/managed-auth ]; then
    rm -rf managed-auth
    cp -a /home/${SSH_USER}/self-hosted-runner/services/managed-auth ./
  else
    echo "WARNING: managed-auth not found on remote workspace; please ensure repo is present at /home/${SSH_USER}/self-hosted-runner or run ansible playbook from control host."
  fi
fi

# Install deps and build (if applicable)
if [ -f managed-auth/package.json ]; then
  cd managed-auth
  export PORT=8080
  if command -v npm >/dev/null 2>&1; then
    npm ci --silent || npm install --no-audit --no-fund --silent
  fi
else
  echo "managed-auth/package.json not present - cannot install dependencies"
fi

# Write systemd unit
cat > /tmp/${SERVICE_NAME}.service <<SYSTEMD
[Unit]
Description=ElevatedIQ API (managed-auth running as API on port 8080)
After=network.target

[Service]
Type=simple
User=${SSH_USER}
WorkingDirectory=${WORKSPACE_DIR}/services/managed-auth
Environment=PORT=8080
ExecStart=/usr/bin/env NODE_ENV=production /usr/bin/node ${WORKSPACE_DIR}/services/managed-auth/index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo mv /tmp/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service
sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}.service
sudo systemctl restart ${SERVICE_NAME}.service || true

echo "Service status:"
sudo systemctl status ${SERVICE_NAME}.service --no-pager || true

# basic healthcheck
sleep 1
if command -v curl >/dev/null 2>&1; then
  curl -sS --fail http://localhost:8080/health && echo "api healthy" || echo "api healthcheck failed"
fi
EOF

echo "Deploy script finished. If the script warned about missing files, consider running the Ansible playbook: ansible-playbook -i inventory/hosts ansible/playbooks/deploy-managed-auth-api.yml"
