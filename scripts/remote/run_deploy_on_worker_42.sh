#!/usr/bin/env bash
set -euo pipefail

# Usage: run_deploy_on_worker_42.sh <ssh_user> [ssh_key_path] [ssh_key_secret_name]
# Examples:
#  ./scripts/remote/run_deploy_on_worker_42.sh ubuntu ~/.ssh/id_rsa
#  ./scripts/remote/run_deploy_on_worker_42.sh ubuntu '' my-ssh-key-secret

USER=${1:-}
KEY=${2:-}
SECRET_NAME=${3:-}
HOST=192.168.168.42
REMOTE_DIR=/home/akushnir/self-hosted-runner
LOGDIR=./logs
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/deploy_worker_42_$(date -u +%Y%m%dT%H%M%SZ).log"

if [ -z "$USER" ]; then
  echo "Usage: $0 <ssh_user> [ssh_key_path]"
  exit 2
fi

SSH_OPTS=( -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new )

# If no key path provided but a secret name is given, fetch the private key
# from Google Secret Manager and use it as a temporary key file.
TMP_KEY_FILE=""
if [ -z "$KEY" ] && [ -n "$SECRET_NAME" ]; then
  PROJECT_ID=${PROJECT_ID:-nexusshield-prod}
  TMP_KEY_FILE=$(mktemp)
  if ! gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT_ID" > "$TMP_KEY_FILE" 2>/dev/null; then
    echo "Failed to fetch SSH key from Secret Manager: $SECRET_NAME (project=$PROJECT_ID)"
    rm -f "$TMP_KEY_FILE" || true
    exit 3
  fi
  chmod 600 "$TMP_KEY_FILE"
  SSH_OPTS+=( -i "$TMP_KEY_FILE" )
elif [ -n "$KEY" ]; then
  SSH_OPTS+=( -i "$KEY" )
fi

# Ensure temporary key is removed on exit
cleanup() {
  if [ -n "$TMP_KEY_FILE" ] && [ -f "$TMP_KEY_FILE" ]; then
    shred -u "$TMP_KEY_FILE" 2>/dev/null || rm -f "$TMP_KEY_FILE"
  fi
}
trap cleanup EXIT

SSH_CMD=(ssh "${SSH_OPTS[@]}" "$USER@$HOST")

echo "Running deploy script on $USER@$HOST; logging to $LOGFILE"

# Remote commands: update repo to branch, run operator script (uses AWS creds on worker)
REMOTE_CMDS="cd $REMOTE_DIR && git fetch origin && git checkout deploy/milestone-organizer-cronjob || true && git pull origin deploy/milestone-organizer-cronjob || true && ./deploy/milestone-organizer-deploy-and-test.sh --aws-profile dev"

# Execute and capture output
if "${SSH_CMD[@]}" "$REMOTE_CMDS" 2>&1 | tee "$LOGFILE"; then
  echo "Remote deploy succeeded"
  exit 0
else
  echo "Remote deploy failed; see $LOGFILE"
  exit 1
fi
