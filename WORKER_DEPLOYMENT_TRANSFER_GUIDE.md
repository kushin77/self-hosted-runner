#!/bin/bash
#
# DEPLOYMENT TRANSFER & EXECUTION GUIDE
# When SSH is not available, use this method
#
# Steps:
# 1. Copy deployment files to USB/network share
# 2. Transfer to dev-elevatediq (192.168.168.42)
# 3. Execute on the worker node
#

set -euo pipefail

readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ============================================================================
# COLOR OUTPUT
# ============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_step() {
  echo -e "${YELLOW}▶${NC} $1"
}

print_success() {
  echo -e "${GREEN}✓${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# FALLBACK DEPLOYMENT METHODS
# ============================================================================

print_section "DEPLOYMENT TRANSFER OPTIONS"

cat << 'EOF'

Since SSH authentication is not available, use one of these methods:

═══════════════════════════════════════════════════════════════════════════

METHOD 1: USB DRIVE TRANSFER (Recommended)
─────────────────────────────────────────

1. Insert USB drive into this machine:
   ls -la /media/$USER/
   mount | grep -i usb

2. Copy deployment files to USB:
   export USB_MOUNT="/media/$USER/USB_DRIVE_NAME"
   cp deploy-standalone.sh "$USB_MOUNT/"
   cp WORKER_DEPLOYMENT_README.md "$USB_MOUNT/"
   cp -r scripts/ "$USB_MOUNT/scripts/" 2>/dev/null || true

3. Eject USB safely:
   sync
   umount "$USB_MOUNT"
   # Remove USB from this machine

4. Insert USB into dev-elevatediq (192.168.168.42):
   ssh <local_access> # or use physical access
   mount /media/usb
   cd /media/usb
   bash deploy-standalone.sh

═══════════════════════════════════════════════════════════════════════════

METHOD 2: NETWORK SHARE (Samba/NFS)
────────────────────────────────────

1. Setup on this machine (if available):
   mkdir -p /tmp/deployment-share
   sudo mount -t cifs //192.168.168.42/share /tmp/deployment-share \
     -o username=<user> 2>/dev/null || true

2. Copy files:
   cp deploy-standalone.sh /tmp/deployment-share/
   cp WORKER_DEPLOYMENT_README.md /tmp/deployment-share/

3. On dev-elevatediq, mount and execute:
   mount -t cifs //192.168.1.X/share /mnt/share
   cd /mnt/share
   bash deploy-standalone.sh

═══════════════════════════════════════════════════════════════════════════

METHOD 3: FILE TRANSFER via rsync (with local access)
──────────────────────────────────────────────────────

If you have local network access to dev-elevatediq:

1. On dev-elevatediq, enable SSH or sftp:
   sudo systemctl start ssh

2. From this machine:
   rsync -avz deploy-standalone.sh \
     automation@192.168.168.42:/home/automation/
   rsync -avz scripts/ \
     automation@192.168.168.42:/home/automation/scripts/

3. Execute on dev-elevatediq:
   bash /home/automation/deploy-standalone.sh

═══════════════════════════════════════════════════════════════════════════

METHOD 4: CONTAINERIZED DEPLOYMENT
───────────────────────────────────

1. Build portable Docker image (if Docker available on worker):
   docker build -f Dockerfile.worker-deploy -t worker-deploy:latest .

2. Transfer image:
   docker save worker-deploy:latest | gzip > worker-deploy.tar.gz
   # Transfer worker-deploy.tar.gz to worker via USB/network

3. On worker node:
   docker load < worker-deploy.tar.gz
   docker run --rm -v /opt:/target worker-deploy:latest

═══════════════════════════════════════════════════════════════════════════

MANUAL DEPLOYMENT (If all else fails)
──────────────────────────────────────

On dev-elevatediq (192.168.168.42), manually:

1. Create directories:
   sudo mkdir -p /opt/automation/{k8s-health-checks,security,multi-region,core,audit}

2. Copy scripts into respective directories:
   # From cloned repo or USB
   cd /path/to/repo
   sudo cp scripts/k8s-health-checks/*.sh /opt/automation/k8s-health-checks/
   sudo cp scripts/security/*.sh /opt/automation/security/
   sudo cp scripts/multi-region/*.sh /opt/automation/multi-region/
   sudo cp scripts/automation/*.sh /opt/automation/core/

3. Set permissions:
   sudo chmod 755 /opt/automation
   sudo chmod 755 /opt/automation/*/*

4. Verify:
   ls -laR /opt/automation/

═══════════════════════════════════════════════════════════════════════════

EOF

# ============================================================================
# DEPLOYMENT VALIDATION
# ============================================================================

print_section "DEPLOYMENT VALIDATION CHECKLIST"

cat << 'EOF'

After deployment, verify on dev-elevatediq (192.168.168.42):

□ Check directories exist:
  ls -la /opt/automation/

□ Verify scripts are executable:
  find /opt/automation -name "*.sh" -exec file {} \;

□ Test syntax of critical scripts:
  for f in /opt/automation/*/*.sh; do bash -n "$f" || echo "FAILED: $f"; done

□ Check audit log created:
  ls -la /opt/automation/audit/

□ Verify Git deployment info (if cloned):
  cd /opt/automation && git log --oneline -5

□ Run initial health check:
  bash /opt/automation/k8s-health-checks/cluster-readiness.sh

EOF

# ============================================================================
# DEPLOYMENT STATUS SUMMARY
# ============================================================================

print_section "DEPLOYMENT STATUS"

print_step "Current Status: SSH Authentication Failed"
print_error "SSH key not authorized on worker node"
echo ""

print_step "Recommended Action:"
print_success "Use METHOD 1 (USB Drive Transfer)"
echo ""
echo "This method requires:"
echo "  • USB drive (8GB+ recommended)"
echo "  • Physical access to dev-elevatediq"
echo "  • No network authentication needed"
echo ""

# Generate transfer checklist
print_section "TRANSFER CHECKLIST"

cat << 'EOF'

Files to Transfer:
□ deploy-standalone.sh                       (2 KB)
□ WORKER_DEPLOYMENT_README.md               (2 KB)
□ scripts/k8s-health-checks/                (~15 KB)
□ scripts/security/                         (~10 KB)
□ scripts/multi-region/                     (~12 KB)
□ scripts/automation/                       (~25 KB)

Total Size: ~65 KB

Transfer Method: USB Drive
Destination: dev-elevatediq (192.168.168.42)
Execution: bash deploy-standalone.sh

Estimated Transfer Time: < 1 minute
Estimated Deployment Time: 3-5 minutes

EOF

# Create portable package
print_section "CREATING PORTABLE DEPLOYMENT PACKAGE"

if command -v tar &>/dev/null && command -v gzip &>/dev/null; then
  PACKAGE_FILE="worker-deployment-${TIMESTAMP}.tar.gz"
  PACKAGE_DIR="/tmp/worker-deployment-$$"
  
  print_step "Creating package: $PACKAGE_FILE"
  
  mkdir -p "$PACKAGE_DIR/deployment"
  
  # Copy deployment scripts
  cp deploy-standalone.sh "$PACKAGE_DIR/deployment/" 2>/dev/null || true
  
  # Create README
  cat > "$PACKAGE_DIR/deployment/README.md" << 'EOFREADME'
# Worker Node Deployment Package

## Quick Start

1. Extract package:
   ```
   tar -xzf worker-deployment-*.tar.gz
   cd deployment
   ```

2. Run deployment:
   ```
   bash deploy-standalone.sh
   ```

## What Gets Deployed

- K8s Health Checks (cluster-readiness.sh, cluster-stuck-recovery.sh)
- Security Audits (audit-test-values.sh, validate-multicloud-secrets.sh)
- Multi-Region Failover (failover-automation.sh)
- Core Automation (credential-manager.sh, orchestrator.sh, deployment-monitor.sh)

All to: /opt/automation

## Output

All deployments logged to: /opt/automation/audit/deployment-*.log

EOFREADME

  # Create MD5 checksum
  (cd "$PACKAGE_DIR" && find . -type f -exec md5sum {} \; > checksums.md5)
  cp "$PACKAGE_DIR/checksums.md5" "$PACKAGE_DIR/deployment/"
  
  # Create archive
  if tar -czf "$PACKAGE_FILE" -C "$PACKAGE_DIR" . 2>/dev/null; then
    print_success "Package created: $PACKAGE_FILE"
    echo ""
    echo "Size: $(du -h $PACKAGE_FILE | cut -f1)"
    echo "Location: $(pwd)/$PACKAGE_FILE"
    echo ""
    echo "Transfer to USB:"
    echo "  cp $PACKAGE_FILE /media/usb/"
    echo ""
    echo "On dev-elevatediq:"
    echo "  tar -xzf worker-deployment-*.tar.gz"
    echo "  cd deployment"
    echo "  bash deploy-standalone.sh"
  else
    print_error "Failed to create archive"
  fi
  
  # Cleanup
  rm -rf "$PACKAGE_DIR"
else
  print_error "tar/gzip not available for package creation"
fi

echo ""
print_section "NEXT STEPS"

cat << 'EOF'

1. Prepare USB Drive
   ─────────────────
   • Insert USB into this machine
   • Mount USB: mount /media/usb
   • Create deployment directory: mkdir -p /media/usb/deployment

2. Copy Deployment Files
   ──────────────────────
   • Copy deploy-standalone.sh
   • Copy scripts/ directory
   • Copy README and checksums

3. Transfer to Worker Node
   ────────────────────────
   • Safely eject USB from this machine
   • Connect USB to dev-elevatediq (192.168.168.42)
   • Mount USB on worker: mount /media/usb

4. Execute Deployment
   ───────────────────
   sudo bash /media/usb/deployment/deploy-standalone.sh

5. Verify Deployment
   ──────────────────
   • Check /opt/automation exists
   • Verify all scripts present and executable
   • Check audit log: /opt/automation/audit/deployment-*.log

6. Enable Automation
   ──────────────────
   • Add cron jobs for periodic checks
   • Configure CI/CD integration
   • Enable CloudWatch monitoring

EOF

print_section "SUPPORT"

echo "If deployment fails:"
echo ""
echo "1. Check deployment log:"
echo "   tail -f /opt/automation/audit/deployment-*.log"
echo ""
echo "2. Verify prerequisites:"
echo "   bash -n deploy-standalone.sh  # Syntax check"
echo ""
echo "3. Manual deployment:"
echo "   Refer to METHOD 4 in this document"
echo ""
