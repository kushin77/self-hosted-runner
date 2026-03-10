#!/usr/bin/env bash
set -euo pipefail

# Usage: deploy-to-remote-host.sh <user@host> [environment] [credentials-path]
# Example: deploy-to-remote-host.sh ubuntu@192.168.168.42 production /home/ubuntu/creds.json

REMOTE="${1:?user@host}"
ENV="${2:-production}"
CREDS="${3:-}" # optional path to credentials on remote host

SCRIPT_REMOTE_DIR="/home/akushnir/self-hosted-runner"
LOCAL_DIR="$PWD"

echo "► Preparing deployment artifacts to remote host: $REMOTE"

# Ensure tar of workspace excluding heavy artifacts
TMP_TAR="/tmp/deploy_artifacts_$(date +%s).tar.gz"

# Pack only necessary files for remote execution
tar --exclude='.git' --exclude='node_modules' --exclude='logs' -czf "$TMP_TAR" \
  scripts/comprehensive-deployment-framework.sh \
  scripts/phase5-complete-automation-enhanced.sh \
  docker-compose.phase6.yml \
  nexusshield/infrastructure/terraform/** \
  COMPREHENSIVE_DEPLOYMENT_FINAL_STATUS.md \
  FINAL_DEPLOYMENT_AUTHORIZATION_SUMMARY.md \
  RCA_ENHANCEMENT_SOLUTION_2026_03_10.md

scp "$TMP_TAR" "$REMOTE":/tmp/ || { echo "scp failed"; exit 1; }

ssh "$REMOTE" bash -lc "'
set -euo pipefail
mkdir -p $SCRIPT_REMOTE_DIR
cd /tmp
rm -rf deploy_unpack && mkdir -p deploy_unpack
tar -xzf $(basename $TMP_TAR) -C deploy_unpack
cp -r deploy_unpack/* $SCRIPT_REMOTE_DIR/
chmod +x $SCRIPT_REMOTE_DIR/scripts/*.sh

# Place credentials if provided
if [[ -n \"$CREDS\" && -f \"$CREDS\" ]]; then
  cp \"$CREDS\" $SCRIPT_REMOTE_DIR/creds.json || true
  export GOOGLE_APPLICATION_CREDENTIALS=$SCRIPT_REMOTE_DIR/creds.json
fi

# Execute comprehensive deployment framework on remote host
cd $SCRIPT_REMOTE_DIR
./scripts/comprehensive-deployment-framework.sh $ENV nexusshield-prod
'" || { echo "remote execution failed"; exit 1; }

# Cleanup local tmp tar
rm -f "$TMP_TAR"

echo "► Remote deployment executed (check remote logs on $REMOTE:$SCRIPT_REMOTE_DIR/logs)" 
