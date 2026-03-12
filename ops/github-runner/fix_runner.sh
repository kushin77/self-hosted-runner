#!/usr/bin/env bash
set -euo pipefail

usage(){
  cat <<EOF
Usage: $0 --host HOST --user USER --workdir WORKDIR

Copies service and compose templates to HOST and installs the systemd unit.

Options:
  --host HOST         Remote host (ssh target)
  --user USER         SSH user
  --workdir WORKDIR   Remote working directory for docker-compose (e.g. /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner)

Example:
  ./fix_runner.sh --host dev-elevatediq --user akushnir --workdir /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner
EOF
}

HOST=""
USER=""
WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --workdir) WORKDIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$HOST" || -z "$USER" || -z "$WORKDIR" ]]; then
  usage
  exit 1
fi

LOCAL_DIR=$(cd "$(dirname "$0")" && pwd)
SERVICE_FILE="$LOCAL_DIR/elevatediq-github-runner.service"
COMPOSE_FILE="$LOCAL_DIR/docker-compose.yml"
REMOTE_UNIT_PATH="/etc/systemd/system/elevatediq-github-runner.service"

echo "Copying files to $USER@$HOST..."
scp "$COMPOSE_FILE" "$USER@$HOST:$WORKDIR/docker-compose.yml"
scp "$SERVICE_FILE" "$USER@$HOST:/tmp/elevatediq-github-runner.service"

echo "Installing unit and reloading systemd on $HOST..."
ssh "$USER@$HOST" bash -e <<'SSH_EOF'
set -euo pipefail
sudo mv /tmp/elevatediq-github-runner.service /etc/systemd/system/elevatediq-github-runner.service
sudo chown root:root /etc/systemd/system/elevatediq-github-runner.service
sudo systemctl daemon-reload
sudo systemctl enable --now elevatediq-github-runner.service
sudo systemctl status elevatediq-github-runner.service --no-pager
SSH_EOF

cat <<EOF
Done. Watch logs with:
  ssh $USER@$HOST sudo journalctl -u elevatediq-github-runner.service -f
Or inspect docker containers:
  ssh $USER@$HOST docker ps --no-trunc | head -n 20
EOF
