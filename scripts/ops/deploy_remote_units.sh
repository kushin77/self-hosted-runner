#!/usr/bin/env bash
set -euo pipefail

# Idempotent deployer for auto_reverify systemd units and helper script to an on-prem host.
# Usage: deploy_remote_units.sh --host HOST --ssh-key /path/to/key --user akushnir --s3-bucket BUCKET --github-token TOKEN --issue 2594

usage(){
  cat <<EOF
Usage: $0 --host HOST --ssh-key /path/to/key [--user USER] [--s3-bucket BUCKET] [--github-token TOKEN] [--issue ISSUE]

This script copies the `auto_reverify` script, service and timer to the remote host,
writes /etc/default/auto_reverify_env, and enables + starts the timer. Idempotent.
EOF
  exit 1
}

HOST=""
SSH_KEY=""
USER="akushnir"
S3_BUCKET=""
GITHUB_TOKEN=""
ISSUE_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --s3-bucket) S3_BUCKET="$2"; shift 2;;
    --github-token) GITHUB_TOKEN="$2"; shift 2;;
    --issue) ISSUE_NUMBER="$2"; shift 2;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$HOST" || -z "$SSH_KEY" ]]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_SCRIPT="$SCRIPT_DIR/auto_reverify.sh"
LOCAL_SERVICE="$SCRIPT_DIR/auto_reverify.service"
LOCAL_TIMER="$SCRIPT_DIR/auto_reverify.timer"

REMOTE_SCRIPT="/usr/local/bin/auto_reverify.sh"
REMOTE_SERVICE="/etc/systemd/system/auto_reverify.service"
REMOTE_TIMER="/etc/systemd/system/auto_reverify.timer"
REMOTE_ENV="/etc/default/auto_reverify_env"

SSH_OPTS=( -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null )

echo "Deploying auto_reverify to $USER@$HOST"

scp "${SSH_OPTS[@]}" "$LOCAL_SCRIPT" "$USER@$HOST:/tmp/auto_reverify.sh.tmp"
scp "${SSH_OPTS[@]}" "$LOCAL_SERVICE" "$USER@$HOST:/tmp/auto_reverify.service.tmp"
scp "${SSH_OPTS[@]}" "$LOCAL_TIMER" "$USER@$HOST:/tmp/auto_reverify.timer.tmp"

ssh "${SSH_OPTS[@]}" "$USER@$HOST" bash -s <<'REMOTE'
set -euo pipefail
TMP_SCRIPT=/tmp/auto_reverify.sh.tmp
TMP_SERVICE=/tmp/auto_reverify.service.tmp
TMP_TIMER=/tmp/auto_reverify.timer.tmp

# remote paths (must match local script expectations)
REMOTE_SCRIPT=/usr/local/bin/auto_reverify.sh
REMOTE_SERVICE=/etc/systemd/system/auto_reverify.service
REMOTE_TIMER=/etc/systemd/system/auto_reverify.timer

install_if_changed(){
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then
    if ! sha1sum -c <(sha1sum "$src" | awk '{print $1"  -"}') &>/dev/null; then
      echo "Updating $dest"
      sudo mv "$src" "$dest"
    else
      echo "$dest is unchanged; skipping"
      sudo rm -f "$src"
    fi
  else
    echo "Installing $dest"
    sudo mv "$src" "$dest"
  fi
}

install_if_changed "$TMP_SCRIPT" "$REMOTE_SCRIPT"
sudo chmod 0755 "$REMOTE_SCRIPT" || true
install_if_changed "$TMP_SERVICE" "$REMOTE_SERVICE"
install_if_changed "$TMP_TIMER" "$REMOTE_TIMER"

sudo systemctl daemon-reload
sudo systemctl enable --now auto_reverify.timer || true
sudo systemctl restart auto_reverify.timer || true
sudo systemctl status auto_reverify.timer --no-pager || true
REMOTE

echo "Writing remote environment file"
ENV_CONTENT="S3_BUCKET=${S3_BUCKET}\nGITHUB_TOKEN=${GITHUB_TOKEN}\nISSUE_NUMBER=${ISSUE_NUMBER:-2594}\n"
ssh "${SSH_OPTS[@]}" "$USER@$HOST" "echo -n '$ENV_CONTENT' | sudo tee $REMOTE_ENV > /dev/null"

echo "Reloading systemd and verifying status on remote host"
ssh "${SSH_OPTS[@]}" "$USER@$HOST" sudo systemctl daemon-reload
ssh "${SSH_OPTS[@]}" "$USER@$HOST" sudo systemctl enable --now auto_reverify.timer
ssh "${SSH_OPTS[@]}" "$USER@$HOST" sudo systemctl status auto_reverify.timer --no-pager || true

echo "Deploy complete. To verify locally: ssh -i $SSH_KEY $USER@$HOST 'systemctl list-timers --all | grep auto_reverify'"

exit 0
