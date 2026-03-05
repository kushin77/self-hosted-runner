#!/usr/bin/env bash
set -euo pipefail

# Usage: ./trigger-plan-when-secrets.sh [interval_seconds] [timeout_seconds]
# Polls GH repository secrets and triggers the terraform plan workflow when all
# required secrets are present. Intended for operator-run automation.

INTERVAL=${1:-15}
TIMEOUT=${2:-900}
REPO="kushin77/self-hosted-runner"
REQUIRED_SECRETS=("GOOGLE_CREDENTIALS" "PROD_TFVARS")

end_time=$((SECONDS + TIMEOUT))
echo "Waiting up to ${TIMEOUT}s for required secrets: ${REQUIRED_SECRETS[*]}"
while [ $SECONDS -lt $end_time ]; do
  missing=()
  for s in "${REQUIRED_SECRETS[@]}"; do
    if ! gh secret list --repo "$REPO" | awk '{print $1}' | grep -qx "$s"; then
      missing+=("$s")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    echo "All required secrets present — dispatching terraform plan workflow"
    gh workflow run terraform-plan-apply.yml --repo "$REPO" --ref main -f auto_apply=false
    echo "Dispatched workflow. Exiting."
    exit 0
  fi

  echo "Still missing: ${missing[*]} — sleeping ${INTERVAL}s"
  sleep "$INTERVAL"
done

echo "Timeout waiting for secrets: ${REQUIRED_SECRETS[*]}" >&2
exit 2
