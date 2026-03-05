#!/usr/bin/env bash
set -euo pipefail
# deploy_to_host.sh user@host [docker|systemd] [branch]

HOST=${1:-}
METHOD=${2:-systemd}
BRANCH=${3:-main}

if [ -z "$HOST" ]; then
  echo "Usage: $0 user@host [docker|systemd] [branch]" >&2
  exit 2
fi

REPO=https://github.com/kushin77/self-hosted-runner.git
REMOTE_DIR=/home/akushnir/runnercloud

echo "Deploying branch '$BRANCH' to $HOST using method '$METHOD'"

ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" bash -s <<EOF
set -euo pipefail
sudo mkdir -p $REMOTE_DIR
if [ -d "$REMOTE_DIR/.git" ]; then
  cd $REMOTE_DIR
  sudo -u $(whoami) git fetch origin --quiet || true
  sudo -u $(whoami) git checkout $BRANCH 2>/dev/null || sudo -u $(whoami) git checkout -B $BRANCH origin/$BRANCH || true
  sudo -u $(whoami) git pull --rebase origin $BRANCH || true
else
  sudo rm -rf $REMOTE_DIR || true
  sudo mkdir -p $REMOTE_DIR
  sudo chown $(whoami) $REMOTE_DIR
  git clone $REPO $REMOTE_DIR
  cd $REMOTE_DIR
  git checkout $BRANCH || true
fi

cd $REMOTE_DIR/services/provisioner-worker/deploy

if [ "$METHOD" = "docker" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found on target host" >&2
    exit 3
  fi
  docker-compose -f docker-compose.yml pull --ignore-pull-failures || true
  docker-compose -f docker-compose.yml up -d
else
  # systemd path
  if [ ! -f provisioner-worker.service ]; then
    echo "provisioner-worker.service not found in deploy directory" >&2
    exit 4
  fi
  sudo cp provisioner-worker.service /etc/systemd/system/provisioner-worker.service
  sudo mkdir -p /var/lib/provisioner-worker
  sudo chown $(whoami) /var/lib/provisioner-worker || true
  sudo systemctl daemon-reload
  sudo systemctl enable --now provisioner-worker
fi
EOF

echo "Deploy command completed. Check $HOST for service status." 
