#!/usr/bin/env bash
# Run Phase 6 quickstart on a remote fullstack host via SSH
# Validates credentials and environment before remote execution
# Usage: FULLSTACK_USER=user FULLSTACK_HOST=host.example.com ./scripts/phase6-remote-runner.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
source "${REPO_ROOT}/scripts/lib/validate_env.sh"
source "${REPO_ROOT}/scripts/lib/load_credentials.sh"

: ${FULLSTACK_USER:?Need FULLSTACK_USER}
: ${FULLSTACK_HOST:?Need FULLSTACK_HOST}
: ${REMOTE_REPO_PATH:="/home/${FULLSTACK_USER}/self-hosted-runner"}
: ${SSH_OPTS:="-o BatchMode=yes -o StrictHostKeyChecking=accept-new"}

TIMESTAMP=$(date -u +"%Y%m%d-%H%M%SZ")
LOG_REMOTE="/tmp/phase6-quickstart-${TIMESTAMP}.log"
LOG_LOCAL="logs/phase6-remote-run-${TIMESTAMP}.log"
AUDIT_LOG="logs/phase6-remote-audit-${TIMESTAMP}.jsonl"
mkdir -p logs

# Validate required environment variables
validate_required_env "FULLSTACK_USER" "FULLSTACK_HOST" || {
  echo "[PHASE6] ERROR: Missing required SSH host parameters" >&2
  exit 1
}

echo "== Phase 6 remote runner (credential-validated) =="
echo "Host: ${FULLSTACK_USER}@${FULLSTACK_HOST}"

# Log execution start
audit_env_access "FULLSTACK_USER" "phase6_remote_execution"
audit_env_access "FULLSTACK_HOST" "phase6_remote_execution"

# Attempt to load SSH key from GSM/Vault (optional enhancement)
SSH_KEY=$(load_credentials "CREDENTIAL_SSH_KEY_DEPLOY_PROD" || echo "")
if [[ -n "$SSH_KEY" ]]; then
  echo "[PHASE6] Loaded SSH key from GSM/Vault"
  SSH_OPTS="${SSH_OPTS} -i /tmp/phase6-ssh-key-${TIMESTAMP}"
  echo "$SSH_KEY" > "/tmp/phase6-ssh-key-${TIMESTAMP}"
  chmod 600 "/tmp/phase6-ssh-key-${TIMESTAMP}"
  trap "rm -f /tmp/phase6-ssh-key-${TIMESTAMP}" EXIT
fi


# Pull latest changes on remote
ssh ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}" \
  "set -euo pipefail; cd ${REMOTE_REPO_PATH} || exit 2; git fetch --all; git reset --hard origin/main"

# Run quickstart on remote and capture remote log
ssh ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}" \
  "set -euo pipefail; cd ${REMOTE_REPO_PATH}; bash scripts/phase6-quickstart.sh 2>&1 | tee ${LOG_REMOTE}; exit \\${PIPESTATUS[0]}"

# Fetch remote logs/artifacts back to local logs/
scp ${SSH_OPTS} "${FULLSTACK_USER}@${FULLSTACK_HOST}:${LOG_REMOTE}" "${LOG_LOCAL}" || true

echo "Remote quickstart finished. Remote log saved to ${LOG_LOCAL}"

echo "You can inspect the log with: tail -n 200 ${LOG_LOCAL}"

exit 0
