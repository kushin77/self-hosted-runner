#!/bin/bash
set -e

# --- Configuration ---
ORG_NAME="elevatediq-ai"
RUNNER_NAME="eiq-org-runner-$(hostname)-$(date +%s)"
RUNNER_LABELS="linux,self-hosted,org-level,ephemeral"
RUNNER_DIR="/home/akushnir/self-hosted-runner/actions-runner"
VERSION="2.312.0" # Example stable version

echo "Initializing Sovereign Org runner for ${ORG_NAME}..."

# 1. Cleanup existing registration
if [ -f "${RUNNER_DIR}/config.sh" ]; then
    echo "Stopping and removing existing runner..."
    cd "${RUNNER_DIR}"
    sudo ./svc.sh stop || true
    sudo ./svc.sh uninstall || true
    ./config.sh remove --token "${GITHUB_TOKEN}" || true
fi

# 2. Re-scaffold for immutability
mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [ ! -f "config.sh" ]; then
    echo "Downloading runner binary..."
    curl -o actions-runner-linux-x64-${VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-x64-${VERSION}.tar.gz
    tar xzf ./actions-runner-linux-x64-${VERSION}.tar.gz
fi

# 3. Get Fresh Org Token via GitHub API
echo "Fetching registration token for ${ORG_NAME}..."
REG_TOKEN=$(gh api --method POST /orgs/"${ORG_NAME}"/actions/runners/registration-token -q .token)

if [ -z "$REG_TOKEN" ] || [ "$REG_TOKEN" == "null" ]; then
    echo "Failed to get registration token via GitHub CLI. Check GITHUB_TOKEN permissions."
    exit 1
fi

# 4. Register at Org Level
echo "Registering runner ${RUNNER_NAME}..."
./config.sh --url "https://github.com/${ORG_NAME}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --unattended \
    --replace \
    --ephemeral

# 5. Install as systemd service for persistence
sudo ./svc.sh install
sudo ./svc.sh start

echo "Sovereign runner ${RUNNER_NAME} is ONLINE at org level."
