#!/usr/bin/env bash
set -euo pipefail

# Install and register GitHub Actions self-hosted runner
# Usage: setup-self-hosted-runner.sh <repo-url> <runner-name> <registration-token> [workdir]
# Example: ./setup-self-hosted-runner.sh https://github.com/kushin77/self-hosted-runner my-runner "TOKEN" /opt/actions-runner

REPO_URL=${1:?repo url e.g. https://github.com/owner/repo}
RUNNER_NAME=${2:?runner name}
TOKEN=${3:?registration token}
WORKDIR=${4:-/opt/actions-runner}

ARCHIVE_URL="https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "Downloading runner to $WORKDIR"
curl -sSL "$ARCHIVE_URL" -o actions-runner.tar.gz

echo "Extracting..."
tar xzf actions-runner.tar.gz
rm -f actions-runner.tar.gz

echo "Configuring runner ($RUNNER_NAME) for $REPO_URL"
./config.sh --unattended --url "$REPO_URL" --token "$TOKEN" --name "$RUNNER_NAME"

echo "Installing service"
sudo ./svc.sh install
sudo ./svc.sh start

echo "Self-hosted runner installed and started (name: $RUNNER_NAME)"

echo "To remove the runner: sudo ./svc.sh stop && sudo ./svc.sh uninstall && ./config.sh remove --token <token>"
