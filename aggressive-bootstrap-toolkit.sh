#!/bin/bash
#
# 🚀 AGGRESSIVE WORKER BOOTSTRAP TOOLKIT
#
# Comprehensive bootstrap strategies for worker node 192.168.168.42
# Implements multiple access paths:
#   1. Password SSH (if enabled)
#   2. Existing SSH key with sudo escalation
#   3. IPMI/console access (if available)
#   4. Serial console
#   5. Physical access (final fallback)
#
# Mandate: Get worker bootstrapped by ANY MEANS NECESSARY
#

set -euo pipefail

WORKER="192.168.168.42"
USER="akushnir"
VERBOSE="${VERBOSE:-false}"

# ============================================================================
# COLORS
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[*]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }

# ============================================================================
# STRATEGY 1: PASSWORD-BASED SSH
# ============================================================================
strategy_password_ssh() {
    log "STRATEGY 1: Password-Based SSH Authorization"
    echo ""
    
    cat << 'EOF'
This strategy uses ssh-copy-id with password authentication.

Prerequisites:
  ✓ Worker has SSH password authentication enabled
  ✓ You know the root or akushnir password

Steps:

1. With ROOT password:
   ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.168.42
   (Enter root password when prompted)

2. With AKUSHNIR password (if user exists):
   ssh-copy-id -i ~/.ssh/id_ed25519.pub akushnir@192.168.168.42
   (Enter akushnir password when prompted)

3. Then verify:
   ssh -i ~/.ssh/id_ed25519 root@192.168.168.42 whoami

4. If successful, remaining setup is automated:
   bash /home/akushnir/self-hosted-runner/deployment-executor-autonomous.sh full
EOF
    
    echo ""
    log "Is password authentication available? (y/n)"
    read -r response
    
    if [ "$response" = "y" ]; then
        log "Attempting ssh-copy-id with root..."
        ssh-copy-id -i ~/.ssh/id_ed25519.pub root@"$WORKER" 2>&1 || {
            log_warn "Root failed, trying $USER..."
            ssh-copy-id -i ~/.ssh/id_ed25519.pub "$USER@$WORKER"
        }
        log_success "SSH key installed via password authentication"
        return 0
    fi
    
    return 1
}

# ============================================================================
# STRATEGY 2: IPMI/BMC CONSOLE ACCESS
# ============================================================================
strategy_ipmi_console() {
    log "STRATEGY 2: IPMI/BMC Console Access"
    echo ""
    
    cat << 'EOF'
This strategy uses IPMI (Intelligent Platform Management Interface) to access the server console.

Common IPMI Tools:
  - ipmitool (command-line)
  - iLO (HP Proliant)
  - iDRAC (Dell)
  - IPMI web interface (http://192.168.168.42:623 equivalent)

Steps:

1. Check if ipmitool is available:
   which ipmitool

2. Try connecting to IPMI:
   ipmitool -I lanplus -H 192.168.168.42 -U root -P PASSWORD chassis power status

3. Get console access:
   ipmitool -I lanplus -H 192.168.168.42 -U root -P PASSWORD sol activate

4. In console, execute bootstrap commands:
   sudo su -
   useradd -m -s /bin/bash akushnir 2>/dev/null || true
   mkdir -p /home/akushnir/.ssh
   chmod 700 /home/akushnir/.ssh
   echo "YOUR_PUBLIC_KEY_HERE" >> /home/akushnir/.ssh/authorized_keys
   chmod 600 /home/akushnir/.ssh/authorized_keys
   chown -R akushnir:akushnir /home/akushnir/.ssh

5. Exit console (Ctrl+]+) and verify SSH access:
   ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.42 whoami
EOF
    
    echo ""
    log "Do you have IPMI/BMC access to worker? (y/n)"
    read -r response
    
    if [ "$response" = "y" ]; then
        log "Please connect to IPMI console and execute the commands above"
        log "Then press ENTER when complete"
        read -r
        return 0
    fi
    
    return 1
}

# ============================================================================
# STRATEGY 3: SERIAL CONSOLE
# ============================================================================
strategy_serial_console() {
    log "STRATEGY 3: Serial Console Access"
    echo ""
    
    cat << 'EOF'
This strategy uses serial console (RS-232 or USB serial).

Prerequisites:
  ✓ Physical serial cable connected
  ✓ Serial terminal available (minicom, picocom, etc.)

Steps:

1. Find serial port:
   ls -la /dev/tty*

2. Connect to serial (example: /dev/ttyUSB0 at 9600 baud):
   sudo minicom -D /dev/ttyUSB0 -b 9600

   Or with picocom:
   sudo picocom -b 9600 /dev/ttyUSB0

3. Boot system (press key to enter bootloader if needed)

4. Log in as root (or use bootloader password)

5. Execute bootstrap commands:
   useradd -m -s /bin/bash akushnir 2>/dev/null || true
   mkdir -p /home/akushnir/.ssh
   chmod 700 /home/akushnir/.ssh
   echo "YOUR_PUBLIC_KEY_HERE" >> /home/akushnir/.ssh/authorized_keys
   chmod 600 /home/akushnir/.ssh/authorized_keys
   chown -R akushnir:akushnir /home/akushnir/.ssh

6. Exit serial (Ctrl+A then Ctrl+X for minicom)

7. Verify SSH access from dev machine:
   ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.42 whoami
EOF
    
    echo ""
    log "Do you have serial console access? (y/n)"
    read -r response
    
    if [ "$response" = "y" ]; then
        log "Please connect to serial console and execute commands above"
        log "Then press ENTER when complete"
        read -r
        return 0
    fi
    
    return 1
}

# ============================================================================
# STRATEGY 4: PHYSICAL CONSOLE ACCESS
# ============================================================================
strategy_physical_console() {
    log "STRATEGY 4: Physical Console Access"
    echo ""
    
    cat << 'EOF'
This strategy uses direct physical access to the worker machine.

Prerequisites:
  ✓ Physical access to worker machine
  ✓ Ability to connect keyboard/monitor or access local terminal

Steps:

1. Connect keyboard, monitor, or access local terminal

2. Log in as root (or press key during boot to enter bootloader)

3. Once logged in, execute bootstrap commands:
   useradd -m -s /bin/bash akushnir 2>/dev/null || true
   mkdir -p /home/akushnir/.ssh
   chmod 700 /home/akushnir/.ssh
   echo YOUR_PUBLIC_KEY >> /home/akushnir/.ssh/authorized_keys
   chmod 600 /home/akushnir/.ssh/authorized_keys
   chown -R akushnir:akushnir /home/akushnir/.ssh

4. Exit to prompt

5. From dev machine, verify SSH works:
   ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.42 whoami

QUICK PUBLIC KEY:
   cat ~/.ssh/id_ed25519.pub | xclip -selection clipboard
   (or use: cat ~/.ssh/id_ed25519.pub)
EOF
    
    echo ""
    log "Do you have physical console access to worker? (y/n)"
    read -r response
    
    if [ "$response" = "y" ]; then
        log "Showing your public key to paste into authorized_keys:"
        echo ""
        cat ~/.ssh/id_ed25519.pub
        echo ""
        log "After pasting this into /home/akushnir/.ssh/authorized_keys"
        log "and setting correct permissions, press ENTER"
        read -r
        return 0
    fi
    
    return 1
}

# ============================================================================
# STRATEGY 5: EXISTING AKUSHNIR ACCESS WITH SUDO
# ============================================================================
strategy_sudoers_escalation() {
    log "STRATEGY 5: Escalation Via Existing Akushnir Access"
    echo ""
    
    cat << 'EOF'
This strategy uses existing SSH access to 'akushnir' user
with sudo privileges to bootstrap from within.

Prerequisites:
  ✓ SSH access to akushnir@192.168.168.42 already working
  ✓ akushnir user in sudoers (can run commands as root)

Steps:

1. Check if akushnir can already SSH in:
   ssh akushnir@192.168.168.42 whoami

2. If yes, use sudo to grant SSH key access:
   ssh akushnir@192.168.168.42 << 'EOF'
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   EOF

3. Verify working:
   ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.42 whoami
EOF
    
    log "Can you already SSH to akushnir@192.168.168.42? (y/n)"
    read -r response
    
    if [ "$response" = "y" ]; then
        log "Attempting to set up authorized_keys for akushnir..."
        
        PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub)
        
        ssh akushnir@"$WORKER" << INNER_EOF
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "✓ SSH key installed"
INNER_EOF
        
        log_success "SSH key installed for akushnir"
        return 0
    fi
    
    return 1
}

# ============================================================================
# VERIFY BOOTSTRAP
# ============================================================================
verify_bootstrap() {
    log "Verifying bootstrap success..."
    sleep 2
    
    if timeout 3 ssh -i ~/.ssh/id_ed25519 "$USER@$WORKER" whoami &>/dev/null; then
        log_success "✅ Bootstrap successful! SSH access confirmed"
        echo ""
        log "Proceeding with full deployment..."
        return 0
    else
        log_error "❌ Bootstrap verification failed"
        echo ""
        log "Troubleshooting:"
        log "  1. Check SSH key permissions: ls -la ~/.ssh/id_ed25519"
        log "  2. Debug SSH: ssh -vvv akushnir@192.168.168.42"
        log "  3. Verify worker is reachable: ping 192.168.168.42"
        return 1
    fi
}

# ============================================================================
# MAIN MENU
# ============================================================================
show_menu() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "🚀 AGGRESSIVE WORKER BOOTSTRAP STRATEGIES"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "Choose a bootstrap strategy:"
    echo ""
    echo "1) Password-Based SSH (ssh-copy-id)"
    echo "2) IPMI/BMC Console Access"
    echo "3) Serial Console Access"
    echo "4) Physical Console Access"
    echo "5) Existing Akushnir Access + Sudo"
    echo "6) Auto-Try All Strategies"
    echo "7) Skip Bootstrap (advanced users only)"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

main() {
    while true; do
        show_menu
        read -p "Choose option (1-7): " choice
        
        case "$choice" in
            1) strategy_password_ssh && verify_bootstrap && break ;;
            2) strategy_ipmi_console && verify_bootstrap && break ;;
            3) strategy_serial_console && verify_bootstrap && break ;;
            4) strategy_physical_console && verify_bootstrap && break ;;
            5) strategy_sudoers_escalation && verify_bootstrap && break ;;
            6)
                log "Attempting all strategies automatically..."
                strategy_password_ssh && verify_bootstrap && break || true
                strategy_sudoers_escalation && verify_bootstrap && break || true
                log_error "No automatic strategy worked"
                log "Please choose a manual strategy above"
                ;;
            7)
                log_warn "Skipping bootstrap. You must manually authorize SSH key:"
                log_warn "  On worker 192.168.168.42:"
                log_warn "    mkdir -p /home/akushnir/.ssh"
                log_warn "    chmod 700 /home/akushnir/.ssh"
                log_warn "    echo 'YOUR_PUBLIC_KEY' > /home/akushnir/.ssh/authorized_keys"
                log_warn "    chmod 600 /home/akushnir/.ssh/authorized_keys"
                log_warn "    chown -R akushnir:akushnir /home/akushnir/.ssh"
                log_warn "Then run this script again and choose 'Skip Bootstrap'"
                break
                ;;
            *)
                log_error "Invalid choice"
                ;;
        esac
    done
}

# ============================================================================
# ENTRY POINT
# ============================================================================
main "$@"
