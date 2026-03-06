#!/usr/bin/env bash
set -euo pipefail

# Install GitHub Actions runner binaries (idempotent).
# Uses RUNNER_VERSION env var (defaults to latest-ish tag string provided by packer).

RUNNER_VERSION=${RUNNER_VERSION:-v1.0.0}
INSTALL_DIR=/opt/actions-runner

echo "==> Preparing actions runner directory ${INSTALL_DIR}"
mkdir -p ${INSTALL_DIR}
chown root:root ${INSTALL_DIR}

if [ -f "${INSTALL_DIR}/.runner_installed" ]; then
  echo "Runner already installed"
  exit 0
fi

ARCH=linux-x64
TARBALL_URL="https://github.com/actions/runner/releases/download/${RUNNER_VERSION}/actions-runner-${ARCH}-${RUNNER_VERSION}.tar.gz"

echo "Downloading runner from ${TARBALL_URL}"
curl -fsSL ${TARBALL_URL} -o /tmp/runner.tar.gz || {
  echo "Failed to download runner tarball; skipping runner installation"
  exit 0
}

tar -xzf /tmp/runner.tar.gz -C ${INSTALL_DIR}
chown -R root:root ${INSTALL_DIR}
chmod -R 0755 ${INSTALL_DIR}

touch ${INSTALL_DIR}/.runner_installed
echo "Runner binaries installed to ${INSTALL_DIR}"
