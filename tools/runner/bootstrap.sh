#!/usr/bin/env bash
set -euo pipefail

# Bootstrap and register a runner with a CI controller (GitHub/Gitea/GitLab).
# Required env vars for GitHub runner registration: RUNNER_URL, RUNNER_TOKEN

INSTALL_DIR=/opt/actions-runner
RUNNER_URL=${RUNNER_URL:-}
RUNNER_TOKEN=${RUNNER_TOKEN:-}
LABELS=${LABELS:-self-hosted,linux,x64}

if [ -z "${RUNNER_URL}" ] || [ -z "${RUNNER_TOKEN}" ]; then
  echo "RUNNER_URL and RUNNER_TOKEN must be set to register the runner"
  exit 2
fi

if [ ! -d "${INSTALL_DIR}" ]; then
  echo "Runner not installed at ${INSTALL_DIR}. Aborting."
  exit 3
fi

cd ${INSTALL_DIR}

if [ -f .runner_registered ]; then
  echo "Runner appears already registered; skipping"
  exit 0
fi

echo "Configuring runner for ${RUNNER_URL}"
./config.sh --unattended --url "${RUNNER_URL}" --token "${RUNNER_TOKEN}" --labels "${LABELS}" --name "$(hostname)-$(date +%s)"

# Install service
./svc.sh install || true
./svc.sh start || true

touch .runner_registered
echo "Runner registration complete"
