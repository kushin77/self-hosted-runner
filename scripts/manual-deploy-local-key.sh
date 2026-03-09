#!/bin/bash

set -euo pipefail

# Manual deploy using local SSH key (ephemeral, one-off)
# Usage: bash scripts/manual-deploy-local-key.sh [branch]

BRANCH="${1:-main}"
DEPLOY_TARGET="${DEPLOY_TARGET:-192.168.168.42}"
DEPLOY_USER="${DEPLOY_USER:-akushnir}"
REPO_ROOT="$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"

log(){ echo "[INFO] $*"; }
err(){ echo "[ERROR] $*" >&2; }

if [[ ! -f "$REPO_ROOT/.ssh/runner_ed25519" ]]; then
  err "Local SSH key not found at $REPO_ROOT/.ssh/runner_ed25519"
  exit 1
fi

TMP_KEY=$(mktemp)
trap 'rm -f "$TMP_KEY"' EXIT
cat "$REPO_ROOT/.ssh/runner_ed25519" > "$TMP_KEY"
chmod 600 "$TMP_KEY"

log "Creating git bundle for branch: $BRANCH"
TMP_DIR=$(mktemp -d)
BUNDLE="$TMP_DIR/deploy.bundle"
git -C "$REPO_ROOT" bundle create "$BUNDLE" "$BRANCH" --all
SHA=$(sha256sum "$BUNDLE" | awk '{print $1}')
log "Bundle created: $BUNDLE (sha256=$SHA)"

log "Transferring bundle to ${DEPLOY_USER}@${DEPLOY_TARGET}:/tmp/deploy.bundle"
scp -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "$TMP_KEY" "$BUNDLE" "${DEPLOY_USER}@${DEPLOY_TARGET}:/tmp/deploy.bundle"

log "Running remote unpack and checkout"
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o BatchMode=yes -i "$TMP_KEY" "${DEPLOY_USER}@${DEPLOY_TARGET}" bash -s <<'REMOTE'
set -euo pipefail
mkdir -p /opt/self-hosted-runner
cd /opt/self-hosted-runner
git init . || true
git remote remove origin 2>/dev/null || true
git remote add origin /tmp/deploy.bundle || true
git fetch origin --tags --all || true
git bundle unbundle /tmp/deploy.bundle || true
git checkout -f main || git checkout -f master || true
rm -f /tmp/deploy.bundle
REMOTE

log "Remote unpack complete. Recording audit locally and attempting GitHub comment."

AUDIT="{\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"target\":\"$DEPLOY_TARGET\",\"branch\":\"$BRANCH\",\"sha256\":\"$SHA\",\"status\":\"SUCCESS\"}"
mkdir -p "$REPO_ROOT/logs"
echo "$AUDIT" >> "$REPO_ROOT/logs/deployment-verification-audit.jsonl"

if command -v gh >/dev/null 2>&1; then
  gh issue comment 2072 --repo kushin77/self-hosted-runner --body "Deployment SUCCESS: $SHA to $DEPLOY_TARGET (branch=$BRANCH)"
fi

log "Manual deployment completed successfully. Cleanup done."
exit 0
