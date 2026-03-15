#!/bin/bash
# ============================================================================
# DEV NODE CONFIGURATION - QUICK DEPLOYMENT CHECKLIST
# ============================================================================
# Target: 192.168.168.31 (Development Workstation)
# Date: March 15, 2026
#
# This file serves as a checklist for deploying NAS integration on dev node
# Each item includes verification commands
#

# ============================================================================
# PHASE 1: PREREQUISITES (5 minutes)
# ============================================================================

echo "===== PHASE 1: Prerequisites ====="

# [ ] Network connectivity to NAS
echo "Test: ping -c 3 192.168.168.100"

# [ ] SSH available
echo "Test: command -v ssh"

# [ ] Rsync installed  
echo "Test: rsync --version"

# [ ] Disk space available
echo "Test: df -h /opt"

# [ ] Current user can sudo
echo "Test: sudo -l"

# ============================================================================
# PHASE 2: RUN SETUP SCRIPT (10 minutes)
# ============================================================================

echo ""
echo "===== PHASE 2: Run Setup Script ====="

# [ ] Navigate to repo
cd /home/akushnir/self-hosted-runner

# [ ] Make setup script executable
chmod +x scripts/nas-integration/setup-dev-node.sh

# [ ] Run setup (requires sudo)
echo "COMMAND: sudo bash scripts/nas-integration/setup-dev-node.sh"
# Uncomment to run: sudo bash scripts/nas-integration/setup-dev-node.sh

# [ ] Verify setup completed without errors
echo "Check: grep 'COMPLETE' setup-output.log"

# ============================================================================
# PHASE 3: SSH KEY SETUP (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 3: SSH Key Setup ====="

# [ ] Verify SSH key was created
echo "Test: ls -la /home/automation/.ssh/nas-push-key"
# Expected: -rw------- 1 automation automation

# [ ] Display public key
echo "Command: cat /home/automation/.ssh/nas-push-key.pub"

# [ ] Send to NAS admin
echo "ACTION: Copy public key above and send to NAS admin for authorized_keys"

# [ ] Record public key fingerprint
echo "Command: ssh-keygen -l -f /home/automation/.ssh/nas-push-key"

# ============================================================================
# PHASE 4: NAS CONNECTIVITY (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 4: NAS Connectivity ====="

# [ ] Test SSH to NAS (after key added)
echo "Test: ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 'echo OK'"
# Expected output: OK

# [ ] Use automation script
echo "Test: bash scripts/nas-integration/dev-node-automation.sh connectivity"
# Expected: ✅ Connected to NAS successfully

# [ ] Verify NAS directories accessible
echo "Test: ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 'ls /home/svc-nas/repositories'"

# ============================================================================
# PHASE 5: VERIFY INSTALLATION (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 5: Verify Installation ====="

# [ ] Check automation scripts installed
echo "Test: ls -la /opt/automation/scripts/nas-integration/"
# Expected files:
# - dev-node-nas-push.sh
# - dev-node-automation.sh
# - healthcheck-worker-nas.sh

# [ ] Check IAC directory created
echo "Test: ls -la /opt/iac-configs/"
# Expected: Directory exists with README.md

# [ ] Check configuration files
echo "Test: ls -la /opt/automation/"
# Expected: dev-node-nas.env, DEV_NODE_QUICKSTART.md

# [ ] Check logs directory
echo "Test: ls -la /var/log/nas-integration/"

# [ ] Check systemd services
echo "Test: sudo systemctl list-unit-files | grep nas"
# Expected: nas-dev-push.service, nas-dev-healthcheck.*

# [ ] Check documentation
echo "Test: ls -la /opt/automation/docs/nas-integration/"

# ============================================================================
# PHASE 6: INITIAL SYNC TEST (10 minutes)
# ============================================================================

echo ""
echo "===== PHASE 6: Initial Sync Test ====="

# [ ] Add test files to IAC
echo "ACTION: Add sample files to /opt/iac-configs/"
# Example:
# mkdir -p /opt/iac-configs/terraform
# echo "# Test" > /opt/iac-configs/terraform/test.tf

# [ ] Check what would be pushed
echo "Test: bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff"

# [ ] Perform initial push
echo "Test: bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push"
# Expected: ✅ Completed successfully

# [ ] Verify files on NAS
echo "Test: ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100 'find /home/svc-nas/repositories/iac -type f | head'"

# [ ] Check audit log
echo "Test: tail -20 /var/log/nas-integration/dev-node-push.log"
# Should show push operation

# ============================================================================
# PHASE 7: WATCH MODE TEST (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 7: Watch Mode Test ====="

# [ ] Understand watch mode
echo "INFO: Watch mode continuously monitors /opt/iac-configs/ for changes"

# [ ] Start watch mode
echo "Command: bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch"
# Note: This runs in foreground - press Ctrl+C to stop

# [ ] In another terminal, edit a file
echo "ACTION: Edit a file in /opt/iac-configs/"
# Example: echo "update" >> /opt/iac-configs/terraform/test.tf

# [ ] Observe automatic push
echo "OBSERVE: Watch mode should detect change and push to NAS"

# [ ] Stop watch mode
echo "ACTION: Press Ctrl+C to stop watch mode"

# ============================================================================
# PHASE 8: HEALTH CHECK (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 8: Health Check ====="

# [ ] Run health check
echo "Test: bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh --verbose"

# [ ] Check status
echo "Test: bash /opt/automation/scripts/nas-integration/dev-node-automation.sh status"

# [ ] Verify systemd health check timer
echo "Test: sudo systemctl list-timers | grep nas"
# Expected: nas-dev-healthcheck.timer

# ============================================================================
# PHASE 9: INTEGRATION VERIFICATION (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 9: Integration Verification ====="

# [ ] Verify worker node can pull
echo "INFO: Worker nodes pull from NAS every 30 minutes"

# [ ] Check worker sync status
echo "Test: ssh automation@192.168.168.42 'tail /var/log/nas-integration/worker-sync.log' 2>/dev/null"

# [ ] Trigger manual worker sync (optional)
echo "Optional: ssh automation@192.168.168.42 'bash scripts/nas-integration/worker-node-nas-sync.sh' 2>/dev/null"

# [ ] Monitor logs
echo "Test: tail -f /var/log/nas-integration/dev-node-push.log"

# ============================================================================
# PHASE 10: DOCUMENTATION REVIEW (5 minutes)
# ============================================================================

echo ""
echo "===== PHASE 10: Documentation Review ====="

# [ ] Read quick start guide
echo "File: /opt/automation/DEV_NODE_QUICKSTART.md"

# [ ] Review full setup guide
echo "File: /opt/automation/docs/nas-integration/DEV_NODE_SETUP.md"

# [ ] Understand data flow
echo "INFO: Dev edits → Push to NAS → Worker pulls (30 min) → Deploy"

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                   DEV NODE SETUP CHECKLIST - COMPLETE                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"

echo ""
echo "QUICK COMMANDS REFERENCE:"
echo ""
echo "  Setup:       sudo bash /opt/automation/scripts/nas-integration/setup-dev-node.sh"
echo "  Push:        bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push"
echo "  Watch:       bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch"
echo "  Diff:        bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff"
echo "  Status:      bash /opt/automation/scripts/nas-integration/dev-node-automation.sh status"
echo "  Health:      bash /opt/automation/scripts/nas-integration/healthcheck-worker-nas.sh"
echo "  Logs:        tail -f /var/log/nas-integration/dev-node-push.log"
echo ""

echo "KEY DIRECTORIES:"
echo "  Local IaC:   /opt/iac-configs/"
echo "  Scripts:     /opt/automation/scripts/nas-integration/"
echo "  Logs:        /var/log/nas-integration/"
echo "  SSH Key:     /home/automation/.ssh/nas-push-key"
echo ""

echo "DATA FLOW:"
echo "  You Edit → /opt/iac-configs/ → bash push → NAS → Worker (every 30 min)"
echo ""

echo "NEXT STEPS:"
echo "  1. Ensure NAS admin has added your SSH public key"
echo "  2. Test connectivity: ssh -i /home/automation/.ssh/nas-push-key svc-nas@192.168.168.100"
echo "  3. Add your infrastructure configs to /opt/iac-configs/"
echo "  4. Push: bash /opt/automation/scripts/nas-integration/dev-node-nas-push.sh push"
echo "  5. Monitor: tail -f /var/log/nas-integration/dev-node-push.log"
echo "  6. Wait 30 min - worker nodes will pull automatically"
echo ""

echo "SUPPORT:"
echo "  Quick Reference: cat /opt/automation/DEV_NODE_QUICKSTART.md"
echo "  Full Guide:      cat /opt/automation/docs/nas-integration/DEV_NODE_SETUP.md"
echo ""
