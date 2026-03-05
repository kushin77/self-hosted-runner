#!/usr/bin/env bash
##
## Install GitHub Actions Runner
## Downloads and unpacks the runner from GitHub.
##
set -euo pipefail

RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_VERSION="${RUNNER_VERSION:-latest}"

NEW_RUNNERVERSION="v$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name[1:]')"
FILENAME="actions-runner-linux-x64-${NEW_RUNNERVERSION#v}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/${NEW_RUNNERVERSION}/${FILENAME}"

echo "Installing GitHub Actions Runner (${NEW_RUNNERVERSION})..."

# Create directories
mkdir -p "${RUNNER_HOME}"
cd "${RUNNER_HOME}"

# Download runner
echo "Downloading from: ${DOWNLOAD_URL}"
curl -L -o "${FILENAME}" "${DOWNLOAD_URL}" || {
  echo "Failed to download runner"
  exit 1
}

# Extract
echo "Extracting runner..."
tar xzf "${FILENAME}"
rm "${FILENAME}"

# Set permissions
chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_HOME}"
chmod +x "${RUNNER_HOME}/run.sh"
chmod +x "${RUNNER_HOME}/config.sh"

echo "✓ Runner installed to ${RUNNER_HOME}"
"${RUNNER_HOME}/bin/Runner.Listener" --version
