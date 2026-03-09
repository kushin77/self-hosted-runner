#!/usr/bin/env bash
set -euo pipefail

# deploy-dry-run.sh
# Usage: ./scripts/deploy-dry-run.sh <worker-host> [user] [ssh-key]

WORKER_HOST="${1:-}"
USER="${2:-deploy}"
SSH_KEY="${3:-~/.ssh/deploy-key}"

if [ -z "$WORKER_HOST" ]; then
  echo "Usage: $0 <worker-host> [user] [ssh-key]"
  exit 2
fi

echo "Performing dry-run deploy to ${USER}@${WORKER_HOST}"

# copy the direct-deploy script and run with --dry-run
scp -i "$SSH_KEY" scripts/direct-deploy.sh "${USER}@${WORKER_HOST}:/tmp/direct-deploy.sh"
ssh -i "$SSH_KEY" "${USER}@${WORKER_HOST}" /bin/bash <<'EOF'
set -euo pipefail
sudo mv /tmp/direct-deploy.sh /opt/app/direct-deploy.sh || true
sudo chmod +x /opt/app/direct-deploy.sh
sudo /opt/app/direct-deploy.sh --dry-run
EOF

echo "Dry-run complete. Check audit logs on the worker and issue #2072 for audit comments."
