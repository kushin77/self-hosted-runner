#!/usr/bin/env bash
set -euo pipefail

# Helper to generate a repo registration token and run the Ansible playbook non-interactively.
# Usage: scripts/ci/provision-runner.sh <owner> <repo> [inventory-file]

OWNER=${1:?owner}
REPO=${2:?repo}
INVENTORY=${3:-ansible/hosts}

echo "Generating registration token for ${OWNER}/${REPO}"
TOKEN_JSON=$(gh api --method POST /repos/${OWNER}/${REPO}/actions/runners/registration-token)
TOKEN=$(echo "$TOKEN_JSON" | jq -r .token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Failed to obtain registration token" >&2
  echo "$TOKEN_JSON"
  exit 1
fi

echo "Token obtained. Running Ansible playbook..."
ansible-playbook -i "$INVENTORY" ansible/playbooks/provision-self-hosted-runner-noninteractive.yml --extra-vars "reg_token=${TOKEN} runner_repo_url=https://github.com/${OWNER}/${REPO}"

echo "Provisioning completed. Verify runners in GitHub repo settings -> Actions -> Runners"
