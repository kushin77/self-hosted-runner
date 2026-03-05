#!/usr/bin/env bash
set -euo pipefail

# auto-run-plan-on-secrets.sh
# Polls GitHub repo secrets and triggers the terraform plan workflow when
# required secrets are present. Logs to /tmp/auto_plan_monitor.log.

REPO_OWNER=${1:-kushin77}
REPO=${2:-self-hosted-runner}
ISSUE_NUMBER=${3:-374}
POLL_INTERVAL=${4:-30}
MAX_ATTEMPTS=${5:-0} # 0 = unlimited

LOG=/tmp/auto_plan_monitor.log
echo "[START $(date -Iseconds)] auto-run-plan-on-secrets for ${REPO_OWNER}/${REPO}" | tee -a "$LOG"

attempt=0
while true; do
  attempt=$((attempt+1))
  echo "[${attempt}] Checking secrets..." | tee -a "$LOG"

  # Query secrets and check for either Vault pair or AWS pair
  secrets=$(gh secret list --repo "${REPO_OWNER}/${REPO}" --limit 500 --json name --jq '.[] | .name' 2>/dev/null || true)

  has_aws_role=$(echo "$secrets" | grep -x "AWS_ROLE_TO_ASSUME" || true)
  has_aws_region=$(echo "$secrets" | grep -x "AWS_REGION" || true)
  has_vault_addr=$(echo "$secrets" | grep -x "VAULT_ADDR" || true)
  has_vault_token=$(echo "$secrets" | grep -x "VAULT_GITHUB_TOKEN" || true)

  if { [ -n "$has_aws_role" ] && [ -n "$has_aws_region" ]; } || { [ -n "$has_vault_addr" ] && [ -n "$has_vault_token" ]; }; then
    echo "Required secrets found. Triggering terraform plan workflow..." | tee -a "$LOG"
    gh workflow run p4-aws-spot-deploy-plan.yml --repo "${REPO_OWNER}/${REPO}" --ref main || {
      echo "Failed to dispatch workflow" | tee -a "$LOG"
      gh issue comment "${REPO_OWNER}/${REPO}#${ISSUE_NUMBER}" --body "Monitor: Attempted to dispatch terraform plan but dispatch failed. Check runner and workflow settings." || true
    }

    run_url="https://github.com/${REPO_OWNER}/${REPO}/actions/runs/"
    gh issue comment --repo "${REPO_OWNER}/${REPO}" --issue-number "$ISSUE_NUMBER" --body "Auto-monitor: Required secrets detected; dispatched terraform plan workflow on \\`main\\`. If the run completes, I'll fetch artifacts and post them here." || true

    echo "Dispatched plan; exiting monitor." | tee -a "$LOG"
    exit 0
  fi

  if [ "$MAX_ATTEMPTS" -ne 0 ] && [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "Max attempts reached ($MAX_ATTEMPTS). Exiting." | tee -a "$LOG"
    exit 2
  fi

  sleep "$POLL_INTERVAL"
done
