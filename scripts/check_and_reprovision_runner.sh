#!/bin/bash
set -e

ORG="elevatediq-ai"
NAME_CONTAINS="eiq-org-runner"
RUNNER_DIR="/home/akushnir/self-hosted-runner/actions-runner"
SCRIPTS_DIR="/home/akushnir/self-hosted-runner/scripts"
PROVISION_SCRIPT="/home/akushnir/self-hosted-runner/scripts/provision_org_runner.sh"

# Ensure gh is available
if ! command -v gh >/dev/null; then
  echo "gh CLI not found"
  # Try to source Vault-provided vars and continue (GitLab migration may use gitlab-runner)
  if [ -x "${SCRIPTS_DIR}/fetch_vault_secrets.sh" ]; then
    . "${SCRIPTS_DIR}/fetch_vault_secrets.sh"
  fi
  exit 2
fi

TOKEN=$(gh auth token || true)
if [ -z "$TOKEN" ]; then
  echo "gh not authenticated; attempting to source Vault secrets and continue"
  if [ -x "${SCRIPTS_DIR}/fetch_vault_secrets.sh" ]; then
    . "${SCRIPTS_DIR}/fetch_vault_secrets.sh"
  fi
  # proceed: some environments may use GitLab instead of GitHub
fi

STATUS=$(gh api /orgs/${ORG}/actions/runners --jq ".runners[] | select(.name | contains(\"${NAME_CONTAINS}\")) | .status" 2>/dev/null || true)
if [ -z "$STATUS" ]; then
  echo "No runner found; provisioning..."
  bash "$PROVISION_SCRIPT"
  # Notify if reprovision occurred
  NOTIFY_SCRIPT="${SCRIPTS_DIR}/notify_health.sh"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "No runner found — reprovisioned org runner on $(hostname)"
  fi
  # push metric (if configured)
  if [ -x "${SCRIPTS_DIR}/push_metric.sh" ] && [ -n "${PUSHGATEWAY_URL}" ]; then
    "${SCRIPTS_DIR}/push_metric.sh" "${PUSHGATEWAY_URL}" "runner_reprovision_total" 1 || true
  fi
  exit 0
fi

if [ "$STATUS" != "\"online\"" ] && [ "$STATUS" != "online" ]; then
  echo "Runner status: $STATUS — reprovisioning..."
  bash "$PROVISION_SCRIPT"
  # Notify if reprovision occurred
  NOTIFY_SCRIPT="${SCRIPTS_DIR}/notify_health.sh"
  if [ -x "$NOTIFY_SCRIPT" ]; then
    "$NOTIFY_SCRIPT" "Runner offline ($STATUS) — reprovisioned org runner on $(hostname)"
  fi
  # push metric (if configured)
  if [ -x "${SCRIPTS_DIR}/push_metric.sh" ] && [ -n "${PUSHGATEWAY_URL}" ]; then
    "${SCRIPTS_DIR}/push_metric.sh" "${PUSHGATEWAY_URL}" "runner_reprovision_total" 1 || true
  fi
else
  echo "Runner is online: $STATUS"
fi
