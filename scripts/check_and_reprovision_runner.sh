#!/bin/bash
set -e

ORG="elevatediq-ai"
NAME_CONTAINS="eiq-org-runner"
RUNNER_DIR="/home/akushnir/self-hosted-runner/actions-runner"
PROVISION_SCRIPT="/home/akushnir/self-hosted-runner/scripts/provision_org_runner.sh"

# Ensure gh is available
if ! command -v gh >/dev/null; then
  echo "gh CLI not found"
  exit 2
fi

TOKEN=$(gh auth token)
if [ -z "$TOKEN" ]; then
  echo "gh not authenticated"
  exit 2
fi

STATUS=$(gh api /orgs/${ORG}/actions/runners --jq ".runners[] | select(.name | contains(\"${NAME_CONTAINS}\")) | .status" || true)
if [ -z "$STATUS" ]; then
  echo "No runner found; provisioning..."
  bash "$PROVISION_SCRIPT"
  # Notify if reprovision occurred
  NOTIFY_SCRIPT="${RUNNER_DIR}/scripts/notify_health.sh"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "No runner found — reprovisioned org runner on $(hostname)"
  fi
  exit 0
fi

if [ "$STATUS" != "\"online\"" ] && [ "$STATUS" != "online" ]; then
  echo "Runner status: $STATUS — reprovisioning..."
  bash "$PROVISION_SCRIPT"
  # Notify if reprovision occurred
  NOTIFY_SCRIPT="${RUNNER_DIR}/scripts/notify_health.sh"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "Runner offline ($STATUS) — reprovisioned org runner on $(hostname)"
  fi
else
  echo "Runner is online: $STATUS"
fi
