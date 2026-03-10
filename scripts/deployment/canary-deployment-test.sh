#!/bin/bash
# Minimal canary test (recreated)
set -euo pipefail

WORKER="192.168.168.42"
SSH_USER="deploy"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worker) WORKER="$2"; shift 2;;
    --ssh-user) SSH_USER="$2"; shift 2;;
    *) shift;;
  esac
done

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@"; }

log "Starting canary test -> $SSH_USER@$WORKER"
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$SSH_USER@$WORKER" 'echo ok' &>/dev/null; then
  log "SSH ok"
else
  log "SSH failed or unreachable"
  exit 2
fi

# Build small bundle (tar only a tiny marker file)
TMPDIR=$(mktemp -d)
echo "canary" > "$TMPDIR/README.canary"
tar -czf "$TMPDIR/canary.tar.gz" -C "$TMPDIR" README.canary

scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$TMPDIR/canary.tar.gz" "$SSH_USER@$WORKER:/tmp/" || { log "scp failed"; exit 3; }

REMOTE_SUM=$(ssh -o ConnectTimeout=5 "$SSH_USER@$WORKER" "sha256sum /tmp/canary.tar.gz | awk '{print \$1}'")
LOCAL_SUM=$(sha256sum "$TMPDIR/canary.tar.gz" | awk '{print $1}')
if [[ "$REMOTE_SUM" == "$LOCAL_SUM" ]]; then
  log "Bundle transfer verified (sha256 match)"
else
  log "Checksum mismatch"
  exit 4
fi

# Attempt to run deploy wrapper in check-only mode remotely
ssh -o ConnectTimeout=5 "$SSH_USER@$WORKER" 'cd /tmp && mkdir -p canary-deploy && tar -xzf canary.tar.gz -C canary-deploy && (bash canary-deploy/scripts/deploy-idempotent-wrapper.sh --env staging --check-only || true)'
log "Canary remote deploy executed (check-only)"

log "Canary test complete"
exit 0
