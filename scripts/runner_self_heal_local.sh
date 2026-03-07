#!/usr/bin/env bash
set -euo pipefail

# Local runbook to perform self-hosted runner recovery on 192.168.168.42
# Usage:
# - Run locally where you have network access to 192.168.168.42 and the
#   private key for the `akushnir` account (or with passwordless sudo).
# - If you have the private key file, set DEPLOY_SSH_KEY_FILE or pass via
#   SSH agent.

HOST=192.168.168.42
USER=akushnir
SSH_KEY_FILE=${DEPLOY_SSH_KEY_FILE:-""}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

if [[ -n "${SSH_KEY_FILE}" && -f "${SSH_KEY_FILE}" ]]; then
  SSH_CMD=(ssh -i "$SSH_KEY_FILE" $SSH_OPTS ${USER}@${HOST})
else
  SSH_CMD=(ssh $SSH_OPTS ${USER}@${HOST})
fi

echo "Checking connectivity to ${USER}@${HOST}..."
"${SSH_CMD[@]}" 'echo connected' || { echo "SSH connectivity failed"; exit 2; }

echo "Attempting to run Ansible playbook on control machine (if available)..."
if command -v ansible-playbook >/dev/null 2>&1 && [[ -d ansible/playbooks ]]; then
  echo "Running local ansible-playbook against staging inventory (will use SSH key)"
  ansible-playbook -i ansible/inventory/staging ansible/playbooks/provision-self-hosted-runner-noninteractive.yml --limit all || true
else
  echo "Ansible not available locally; falling back to direct SSH restart commands"
  echo "Restarting runner services on host (${HOST}) as ${USER} (may require sudo)"
  "${SSH_CMD[@]}" "sudo systemctl daemon-reload || true; sudo systemctl restart actions-runner.service || sudo systemctl restart runner.service || sudo systemctl restart 'actions.runner.*' || true"
  echo "Fetching recent journal logs for the runner service (last 200 lines)"
  "${SSH_CMD[@]}" "sudo journalctl -u actions-runner --no-pager -n 200 || sudo journalctl -u runner.service --no-pager -n 200 || true"
fi

echo "Verify GitHub runner status from this machine (optional):"
if command -v gh >/dev/null 2>&1; then
  echo "Listing repository runners via GH CLI (requires appropriate token)"
  gh api /repos/kushin77/self-hosted-runner/actions/runners --jq '.runners[] | {name,status}' || true
else
  echo "Install GH CLI to verify runner status locally: https://cli.github.com/"
fi

echo "Runbook complete. If runners remain offline, provide a PAT as the repo secret RUNNER_MGMT_TOKEN or install the public key for DEPLOY_SSH_KEY into /home/akushnir/.ssh/authorized_keys on the host."
