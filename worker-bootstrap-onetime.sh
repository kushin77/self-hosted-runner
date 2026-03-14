#!/bin/bash
#
# 🔧 WORKER NODE BOOTSTRAP - ONE-TIME SETUP (Run as root on worker 192.168.168.42)
#
# This script performs initial SSH key installation on the worker node.
# Execute ONCE on the worker: bash /tmp/worker-bootstrap.sh
#
# After this runs, all subsequent deployments are hands-off ONLY.
#
# MANDATE COMPLIANCE:
#   First Run: One-time manual bootstrap (required for on-prem security)
#   Subsequent: Full automation via GSM, no further intervention needed
#
# Prerequisites for runner:
#   - Physical console access OR
#   - SSH with password authentication OR  
#   - Existing user with sudo access
#
# Usage:
#   # On worker node (192.168.168.42):
#   curl -fsSL https://your-repo/worker-bootstrap.sh | bash
#   # OR
#   bash /tmp/worker-bootstrap.sh
#
# This script:
#   1. Creates /home/akushnir if needed
#   2. Creates /home/akushnir/.ssh directory
#   3. Removes existing authorized_keys
#   4. (Will be populated by GSM automation after this)
#   5. Sets correct permissions

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Verify running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must run as root"
    echo "Usage: sudo bash worker-bootstrap.sh"
    exit 1
fi

log_info "Worker Node Bootstrap Starting..."
log_info "Target: 192.168.168.42 (on-prem worker)"
echo ""

# Create akushnir user if needed
if id akushnir &>/dev/null; then
    log_success "User 'akushnir' already exists"
else
    log_info "Creating user 'akushnir'..."
    useradd -m -s /bin/bash akushnir
    log_success "User 'akushnir' created"
fi

# Create SSH directory
log_info "Setting up SSH directory..."
mkdir -p /home/akushnir/.ssh
chmod 700 /home/akushnir/.ssh
chown akushnir:akushnir /home/akushnir/.ssh

# Initialize authorized_keys (empty, will be populated by GSM automation)
touch /home/akushnir/.ssh/authorized_keys
chmod 600 /home/akushnir/.ssh/authorized_keys
chown akushnir:akushnir /home/akushnir/.ssh/authorized_keys

log_success "SSH directory configured"
echo ""

# Verify setup
log_info "Verifying setup..."
[ -d /home/akushnir/.ssh ] && log_success "✓ SSH directory exists"
[ -f /home/akushnir/.ssh/authorized_keys ] && log_success "✓ authorized_keys exists"
[ "$(stat -c %a /home/akushnir/.ssh)" = "700" ] && log_success "✓ SSH directory permissions correct"
[ "$(stat -c %a /home/akushnir/.ssh/authorized_keys)" = "600" ] && log_success "✓ authorized_keys permissions correct"

echo ""
log_success "Worker Bootstrap Complete!"
echo ""
echo "Next Steps:"
echo "  1. Run SSH distribution from dev machine:"
echo "     cd /home/akushnir/self-hosted-runner"
echo "     bash deploy-ssh-credentials-via-gsm.sh distribute-only"
echo ""
echo "  2. Then run full deployment:"
echo "     bash deploy-orchestrator.sh full"
echo ""
echo "After this, deployments are FULLY AUTOMATED (hands-off)."
