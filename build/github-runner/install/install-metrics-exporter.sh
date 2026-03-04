#!/usr/bin/env bash
set -euo pipefail

# Installer: copy exporter and enable systemd user unit on remote runner host (.42)
HOST=192.168.168.42
USER=akushnir
REPO_DIR="/home/${USER}/ElevatedIQ-Mono-Mono-Repo"
REMOTE_DIR="/home/${USER}/EIQ_RUNNER_METRICS"

echo "Creating remote dirs on ${HOST}..."
ssh ${USER}@${HOST} "mkdir -p ~/.config/systemd/user && mkdir -p ${REMOTE_DIR}"

echo "Copying metrics_exporter.py to ${HOST}:${REMOTE_DIR}/"
scp ${REPO_DIR}/build/github-runner/metrics_exporter.py ${USER}@${HOST}:${REMOTE_DIR}/metrics_exporter.py

echo "Copying systemd unit to user's systemd directory"
scp ${REPO_DIR}/build/github-runner/systemd/metrics_exporter.service ${USER}@${HOST}:~/.config/systemd/user/metrics_exporter.service

echo "Reloading user systemd and enabling service"
ssh ${USER}@${HOST} "systemctl --user daemon-reload && systemctl --user enable --now metrics_exporter.service || systemctl --user restart metrics_exporter.service || true"

echo "Done. Use 'ssh ${USER}@${HOST} systemctl --user status metrics_exporter.service' to verify."
