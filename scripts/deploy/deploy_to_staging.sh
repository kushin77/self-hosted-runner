#!/usr/bin/env bash
set -euo pipefail
# Deploy built artifacts and systemd units to a staging host (CI-less)
# Usage: ./deploy_to_staging.sh user@staging-host [branch]

REMOTE=${1:-}
BRANCH=${2:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}
if [ -z "$REMOTE" ]; then
  echo "Usage: $0 user@host [branch]" >&2
  exit 2
fi

TMP_TAR=/tmp/nexusshield_deploy_${RANDOM}.tar.gz
BASENAME=$(basename "$TMP_TAR")

echo "Packing minimal deploy artifacts for branch $BRANCH..."
git archive --format=tar "$BRANCH" scripts systemd backend backend/docker-entrypoint.sh backend/package.json backend/src backend/prisma | gzip -c > "$TMP_TAR"

echo "Uploading to ${REMOTE} and deploying..."
scp -q "$TMP_TAR" "${REMOTE}:/tmp/${BASENAME}" || (echo "scp failed" && exit 3)

ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$REMOTE" bash -s <<EOF
set -euo pipefail
DEPLOY_DIR=/opt/nexusshield
sudo mkdir -p "\$DEPLOY_DIR"
sudo tar xzf /tmp/${BASENAME} -C "\$DEPLOY_DIR"
sudo chown -R root:root "\$DEPLOY_DIR"
# Install systemd units if provided
if [ -d "\$DEPLOY_DIR/systemd" ]; then
  sudo cp -v "\$DEPLOY_DIR/systemd/"*.service /etc/systemd/system/ || true
  # Also install any units placed under scripts/systemd (some units live there)
  if [ -d "\$DEPLOY_DIR/scripts/systemd" ]; then
    sudo cp -v "\$DEPLOY_DIR/scripts/systemd/"*.service /etc/systemd/system/ || true
  fi
  sudo systemctl daemon-reload || true
  # Enable our services if present
  sudo systemctl enable --now cloudrun.service || true
  sudo systemctl enable --now redis-worker.service || true
fi
  # Ensure a virtualenv exists under /opt/nexusshield and install python deps there
  if [ -f "\$DEPLOY_DIR/scripts/cloudrun/requirements.txt" ]; then
    sudo python3 -m venv "\$DEPLOY_DIR/venv" || true
    sudo "\$DEPLOY_DIR/venv/bin/pip" install --upgrade pip || true
    sudo "\$DEPLOY_DIR/venv/bin/pip" install -r "\$DEPLOY_DIR/scripts/cloudrun/requirements.txt" || true
  fi
echo "Deployed to staging at \$(hostname)"
EOF

rm -f "$TMP_TAR"
echo "Deployment finished. Check systemctl status cloudrun.service on ${REMOTE}."
