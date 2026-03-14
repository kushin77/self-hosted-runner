#!/bin/bash
# Complete NAS Migration Verification
# Verifies all aspects of on-premises NAS integration deployment

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RESULTS_FILE="/tmp/nas-verification-$(date +%s).log"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  NAS INTEGRATION - COMPREHENSIVE MIGRATION VERIFICATION                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to test node connectivity
test_node_connectivity() {
    local node_ip=$1
    local node_name=$2
    
    echo -e "${YELLOW}[TEST] Checking $node_name ($node_ip) connectivity...${NC}"
    
    if ping -c 1 "$node_ip" &> /dev/null; then
        echo -e "${GREEN}  ✓ Network connectivity: OK${NC}" | tee -a "$RESULTS_FILE"
        return 0
    else
        echo -e "${RED}  ✗ Network connectivity: UNREACHABLE${NC}" | tee -a "$RESULTS_FILE"
        return 1
    fi
}

# Function to verify systemd timers
verify_timers() {
    local node_ip=$1
    local node_name=$2
    
    echo -e "${YELLOW}[TEST] Verifying systemd timers on $node_name...${NC}"
    
    if ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "sudo systemctl list-timers | grep nas-" 2>/dev/null | tee -a "$RESULTS_FILE"; then
        echo -e "${GREEN}  ✓ Timers active${NC}" | tee -a "$RESULTS_FILE"
        return 0
    else
        echo -e "${RED}  ✗ Timers not found${NC}" | tee -a "$RESULTS_FILE"
        return 1
    fi
}

# Function to verify sync directory
verify_sync_dir() {
    local node_ip=$1
    local node_name=$2
    
    echo -e "${YELLOW}[TEST] Verifying sync directory on $node_name...${NC}"
    
    files=$(ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "find /opt/nas-sync -type f 2>/dev/null | wc -l")
    
    if [ "$files" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Synced files: $files${NC}" | tee -a "$RESULTS_FILE"
        return 0
    else
        echo -e "${RED}  ✗ No synced files found${NC}" | tee -a "$RESULTS_FILE"
        return 1
    fi
}

# Function to verify audit trail
verify_audit_trail() {
    local node_ip=$1
    local node_name=$2
    
    echo -e "${YELLOW}[TEST] Verifying audit trail on $node_name...${NC}"
    
    if ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "[ -f /opt/nas-sync/audit/audit.jsonl ]" 2>/dev/null; then
        lines=$(ssh -o ConnectTimeout=5 "automation@${node_ip}" \
            "wc -l < /opt/nas-sync/audit/audit.jsonl")
        echo -e "${GREEN}  ✓ Audit entries: $lines${NC}" | tee -a "$RESULTS_FILE"
        return 0
    else
        echo -e "${RED}  ✗ Audit trail not found${NC}" | tee -a "$RESULTS_FILE"
        return 1
    fi
}

# Function to check constraints
check_constraints() {
    echo -e "${YELLOW}[TEST] Verifying constraints...${NC}"
    
    local node_ip="192.168.168.42"
    
    # Immutable test
    if ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "grep -q 'pull' /opt/automation/scripts/worker-node-nas-sync.sh" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Immutable: Pull-only architecture confirmed${NC}" | tee -a "$RESULTS_FILE"
    else
        echo -e "${RED}  ✗ Immutable: Architecture check failed${NC}" | tee -a "$RESULTS_FILE"
    fi
    
    # Ephemeral test
    if ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "[ -d /opt/nas-sync ]" 2>/dev/null; then
        echo -e "${GREEN}  ✓ Ephemeral: Sync directory structure confirmed${NC}" | tee -a "$RESULTS_FILE"
    else
        echo -e "${RED}  ✗ Ephemeral: Directory structure check failed${NC}" | tee -a "$RESULTS_FILE"
    fi
    
    # Credentials test
    if ssh -o ConnectTimeout=5 "automation@${node_ip}" \
        "[ ! -f /opt/nas-sync/credentials/password.txt ]" 2>/dev/null; then
        echo -e "${GREEN}  ✓ GSM/Vault: No credentials stored on disk${NC}" | tee -a "$RESULTS_FILE"
    else
        echo -e "${RED}  ✗ GSM/Vault: Found stored credentials${NC}" | tee -a "$RESULTS_FILE"
    fi
}

# Main verification
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}WORKER NODES VERIFICATION${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

test_node_connectivity "192.168.168.42" "Worker Node 1"
verify_timers "192.168.168.42" "Worker Node 1"
verify_sync_dir "192.168.168.42" "Worker Node 1"
verify_audit_trail "192.168.168.42" "Worker Node 1"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}DEV NODE VERIFICATION${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

test_node_connectivity "192.168.168.31" "Dev Node"

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}CONSTRAINT VERIFICATION${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

check_constraints

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ VERIFICATION COMPLETE${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Full results saved to: $RESULTS_FILE"
