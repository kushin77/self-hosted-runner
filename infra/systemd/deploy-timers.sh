#!/bin/bash
# ==================================================================
# PRODUCTION SYSTEMD TIMER DEPLOYMENT
# ==================================================================
# Lead Engineer Approved - Direct Deployment
# Purpose: Deploy daily automation timers for key rotation and maintenance
# ==================================================================

set -euo pipefail

REPO_DIR="/home/akushnir/self-hosted-runner"
SYSTEMD_SOURCE="$REPO_DIR/infra/systemd"
SYSTEMD_DEST="/etc/systemd/system"

echo "==============================================="
echo "🚀 PRODUCTION SYSTEMD DEPLOYMENT"
echo "==============================================="
echo "Repository: $REPO_DIR"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "User: $(whoami)"
echo ""

# Verify running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
  echo "❌ ERROR: This script must be run with sudo (root access required)"
  echo ""
  echo "Try: sudo bash $0"
  exit 1
fi

echo "✅ Running as root (sudo)"
echo ""

# ==================================================================
# STEP 1: Deploy Deployer Key Rotation Timer
# ==================================================================
echo "STEP 1: Deploy Deployer Key Rotation (daily 2 AM UTC)"
echo "---"

if [ -f "$SYSTEMD_SOURCE/deployer-key-rotate.service" ]; then
  echo "Copying deployer-key-rotate.service..."
  cp "$SYSTEMD_SOURCE/deployer-key-rotate.service" "$SYSTEMD_DEST/"
  echo "✅ Service copied"
else
  echo "❌ ERROR: $SYSTEMD_SOURCE/deployer-key-rotate.service not found"
  exit 1
fi

if [ -f "$SYSTEMD_SOURCE/deployer-key-rotate.timer" ]; then
  echo "Copying deployer-key-rotate.timer..."
  cp "$SYSTEMD_SOURCE/deployer-key-rotate.timer" "$SYSTEMD_DEST/"
  echo "✅ Timer copied"
else
  echo "❌ ERROR: $SYSTEMD_SOURCE/deployer-key-rotate.timer not found"
  exit 1
fi

echo ""

# ==================================================================
# STEP 2: Reload Systemd Configuration
# ==================================================================
echo "STEP 2: Reload systemd configuration"
echo "---"
systemctl daemon-reload
echo "✅ Systemd configuration reloaded"
echo ""

# ==================================================================
# STEP 3: Enable & Start Timers
# ==================================================================
echo "STEP 3: Enable and start timers"
echo "---"

echo "Enabling deployer-key-rotate.timer..."
systemctl enable deployer-key-rotate.timer
echo "✅ Timer enabled (will auto-start on boot)"

echo "Starting deployer-key-rotate.timer..."
systemctl start deployer-key-rotate.timer
echo "✅ Timer started (next run at 2 AM UTC)"

echo ""

# ==================================================================
# STEP 4: Verify Deployment
# ==================================================================
echo "STEP 4: Verify deployment"
echo "---"

echo "Timer status:"
systemctl status deployer-key-rotate.timer --no-pager | head -10

echo ""
echo "Next scheduled runs:"
systemctl list-timers deployer-key-rotate.timer --no-pager

echo ""

# ==================================================================
# STEP 5: Verify Service Files
# ==================================================================
echo "STEP 5: Verify service files in systemd"
echo "---"

if systemctl is-active deployer-key-rotate.timer >/dev/null 2>&1; then
  echo "✅ deployer-key-rotate.timer is ACTIVE"
else
  echo "❌ deployer-key-rotate.timer is NOT active"
  exit 1
fi

echo ""

# ==================================================================
# STEP 6: Record Deployment in Audit Log
# ==================================================================
AUDIT_DIR="$REPO_DIR/logs/systemd-deployment"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/deployment-$(date +%Y%m%d-%H%M%S).jsonl"

cat > "$AUDIT_FILE" << EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","level":"INFO","message":"Systemd Deployment: deployer-key-rotate.timer","event":"enabled","user":"$(whoami)"}
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","level":"INFO","message":"Service location: $SYSTEMD_DEST/deployer-key-rotate.service","event":"deployed"}
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","level":"INFO","message":"Timer location: $SYSTEMD_DEST/deployer-key-rotate.timer","event":"deployed"}
EOF

echo "Deployment recorded: $AUDIT_FILE"
echo ""

# ==================================================================
# DEPLOYMENT COMPLETE
# ==================================================================
echo "==============================================="
echo "✅ DEPLOYMENT COMPLETE"
echo "==============================================="
echo ""
echo "Daily Automation Schedule:"
echo "  • 02:00 UTC - Deployer SA key rotation"
echo "  • Immutable audit trail: logs/multi-cloud-audit/owner-rotate-*.jsonl"
echo ""
echo "Monitor:"
echo "  sudo journalctl -u deployer-key-rotate.service -f"
echo ""
echo "Verify next run:"
echo "  sudo systemctl list-timers deployer-key-rotate.timer"
echo ""
echo "==============================================="
