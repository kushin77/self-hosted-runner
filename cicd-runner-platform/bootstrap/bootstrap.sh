#!/usr/bin/env bash
##
## CICD Runner Self-Bootstrap Script (Linux)
## This script runs on machine boot to self-provision a CI/CD runner.
##
## Usage: ./bootstrap.sh
##        Environment variables: RUNNER_REPO, RUNNER_TOKEN, RUNNER_URL, RUNNER_LABELS
##
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
LOG_FILE="/var/log/runner-bootstrap.log"

# Default values
RUNNER_REPO="${RUNNER_REPO:-https://github.com/YOUR_ORG/self-hosted-runner}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_URL="${RUNNER_URL:-https://github.com}"
RUNNER_LABELS="${RUNNER_LABELS:-linux,self-hosted}"
RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[BOOTSTRAP]${NC} $*" | tee -a "${LOG_FILE}"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
  exit 1
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "${LOG_FILE}"
}

log "Starting CI/CD runner bootstrap at $(date)"
log "Runner home: ${RUNNER_HOME}"
log "Runner user: ${RUNNER_USER}"

# 1. Verify host security posture
log "Step 1: Verifying host security..."
"${SCRIPT_DIR}/verify-host.sh" || error "Host verification failed"

# 2. Install base dependencies
log "Step 2: Installing dependencies..."
"${SCRIPT_DIR}/install-dependencies.sh" || error "Dependency installation failed"

# 3. Create runner user and directory
log "Step 3: Configuring runner user and directories..."
if ! id "${RUNNER_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${RUNNER_USER}" || warn "Runner user may already exist"
fi
mkdir -p "${RUNNER_HOME}"
chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"

# 4. Clone runner platform repo
log "Step 4: Cloning runner platform repository..."
git clone "${RUNNER_REPO}" "${PROJECT_ROOT}" 2>&1 | tee -a "${LOG_FILE}"

# 5. Install runner
log "Step 5: Installing GitHub Actions runner..."
"${PROJECT_ROOT}/runner/install-runner.sh" || error "Runner installation failed"

# 6. Register runner
log "Step 6: Registering runner..."
"${PROJECT_ROOT}/runner/register-runner.sh" \
  --url="${RUNNER_URL}" \
  --token="${RUNNER_TOKEN}" \
  --labels="${RUNNER_LABELS}" \
  || error "Runner registration failed"

# 7. Setup systemd service
log "Step 7: Configuring systemd service..."
cat > /etc/systemd/system/actions-runner.service <<EOF
[Unit]
Description=GitHub Actions Runner
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=${RUNNER_USER}
WorkingDirectory=${RUNNER_HOME}
ExecStart=${RUNNER_HOME}/run.sh
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable actions-runner.service

# 8. Setup observability
log "Step 8: Configuring observability agents..."
"${PROJECT_ROOT}/observability/metrics-agent.yaml" || warn "Metrics config optional"

# 9. Verify installation
log "Step 9: Verifying runner installation..."
"${RUNNER_HOME}/run.sh" --version || error "Runner verification failed"

log "Bootstrap complete! Runner will start on next boot or via: systemctl start actions-runner.service"
log "Monitor with: journalctl -u actions-runner.service -f"
