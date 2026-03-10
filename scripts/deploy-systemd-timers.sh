#!/bin/bash
# Deploy systemd service/timer files for automated operations
# Phase 2 deployment script - installs all recurring automation

set -e

echo "=== Phase 2: Systemd Timer Installation ==="
echo "$(date '+%Y-%m-%d %H:%M:%S UTC')" | tr -d '\n' > /tmp/phase2-start.txt && echo " - Starting Phase 2 deployment" >> /tmp/phase2-start.txt

# Install files
echo "Installing systemd files to /etc/systemd/system/..."
cp scripts/systemd/*.service /etc/systemd/system/ || echo "Warning: Service copy had issues"
cp scripts/systemd/*.timer /etc/systemd/system/ || echo "Warning: Timer copy had issues"

# Create log directory
mkdir -p /var/log/nexusshield
chmod 755 /var/log/nexusshield

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start timers
echo "Enabling timers..."
systemctl enable nexusshield-credential-rotation.timer
systemctl enable nexusshield-terraform-backup.timer
systemctl enable nexusshield-compliance-audit.timer

echo "Starting timers..."
systemctl start nexusshield-credential-rotation.timer
systemctl start nexusshield-terraform-backup.timer
systemctl start nexusshield-compliance-audit.timer

# Verify installation
echo ""
echo "=== Timer Installation Verification ==="
echo "Credential Rotation Timer:"
systemctl status nexusshield-credential-rotation.timer --no-pager || true

echo ""
echo "Terraform Backup Timer:"
systemctl status nexusshield-terraform-backup.timer --no-pager || true

echo ""
echo "Compliance Audit Timer:"
systemctl status nexusshield-compliance-audit.timer --no-pager || true

echo ""
echo "=== Listing all installed timers ==="
systemctl list-timers nexusshield-* --no-pager || true

echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S UTC')" | tr -d '\n' > /tmp/phase2-complete.txt && echo " - Phase 2 deployment complete" >> /tmp/phase2-complete.txt

echo "✅ Phase 2 Complete: Systemd timers installed and active"
