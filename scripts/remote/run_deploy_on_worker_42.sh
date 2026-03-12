#!/usr/bin/env bash
set -euo pipefail

# Usage: run_deploy_on_worker_42.sh <ssh_user> [ssh_key_path]
# Example: ./scripts/remote/run_deploy_on_worker_42.sh ubuntu ~/.ssh/id_rsa

USER=${1:-}
KEY=${2:-}
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
if [ -n "$KEY" ]; then
  SSH_OPTS+=( -i "$KEY" )
fi

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
