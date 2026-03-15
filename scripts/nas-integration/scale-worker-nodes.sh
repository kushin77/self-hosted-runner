#!/bin/bash
# Scale NAS Integration to Additional Worker Nodes
# Deploys NAS sync to new on-premises worker nodes
# Usage: ./scale-worker-nodes.sh <node_ip> [node_ip2] [node_ip3]
# Example: ./scale-worker-nodes.sh 192.168.168.43 192.168.168.44 192.168.168.45

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NODE_IPS=("$@")

if [ ${#NODE_IPS[@]} -eq 0 ]; then
    echo -e "${RED}Error: No node IPs provided${NC}"
    echo "Usage: $0 <node_ip> [node_ip2] [node_ip3]"
    echo "Example: $0 192.168.168.43 192.168.168.44"
    exit 1
fi

echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}NAS INTEGRATION SCALER - Deploy to Multiple Worker Nodes${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

DEPLOYMENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOYMENT_LOG="/tmp/nas-scale-deployment-$(date +%s).log"

echo "[SCALER] Starting deployment to ${#NODE_IPS[@]} new worker node(s)..."
echo "[SCALER] Log: $DEPLOYMENT_LOG"
echo ""

# Function to deploy to a single node
deploy_node() {
    local node_ip=$1
    local node_num=$2
    
    echo -e "${YELLOW}[DEPLOY] Node $node_num: Deploying to $node_ip${NC}"
    
    # Create deployment script for this node
    cat > /tmp/deploy-nas-worker-${node_ip}.sh << 'WORKER_DEPLOY'
#!/bin/bash
set -e

echo "[WORKER-$1] Starting deployment..."

# Create directories
mkdir -p /opt/automation/scripts /opt/nas-sync/{iac,configs,credentials,audit}
chmod 700 /opt/nas-sync/credentials

# Pull latest code
cd ~/self-hosted-runner
git pull origin main 2>/dev/null || true

# Install scripts
cp scripts/nas-integration/worker-node-nas-sync.sh /opt/automation/scripts/ 2>/dev/null || true
cp scripts/nas-integration/healthcheck-worker-nas.sh /opt/automation/scripts/ 2>/dev/null || true
chmod 755 /opt/automation/scripts/*.sh

# Install systemd services
sudo cp systemd/nas-worker-sync.service /etc/systemd/system/ 2>/dev/null || true
sudo cp systemd/nas-worker-sync.timer /etc/systemd/system/ 2>/dev/null || true
sudo cp systemd/nas-worker-healthcheck.service /etc/systemd/system/ 2>/dev/null || true
sudo cp systemd/nas-worker-healthcheck.timer /etc/systemd/system/ 2>/dev/null || true
sudo cp systemd/nas-integration.target /etc/systemd/system/ 2>/dev/null || true

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable nas-integration.target
sudo systemctl start nas-integration.target

echo "[WORKER-$1] Deployment complete"
WORKER_DEPLOY
    chmod +x /tmp/deploy-nas-worker-${node_ip}.sh
    
    # Execute deployment via SSH
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new "automation@${node_ip}" "bash -s ${node_ip}" < /tmp/deploy-nas-worker-${node_ip}.sh >> "$DEPLOYMENT_LOG" 2>&1; then
        echo -e "${GREEN}[✓] Node $node_num ($node_ip): DEPLOYED${NC}"
        return 0
    else
        echo -e "${RED}[✗] Node $node_num ($node_ip): FAILED${NC}"
        return 1
    fi
}

# Deploy to all nodes
DEPLOYED=0
FAILED=0

for i in "${!NODE_IPS[@]}"; do
    node_ip="${NODE_IPS[$i]}"
    node_num=$((i+1))
    
    if deploy_node "$node_ip" "$node_num"; then
        ((DEPLOYED++))
    else
        ((FAILED++))
    fi
    
    echo ""
done

# Summary
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}DEPLOYMENT SUMMARY${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo "Successfully deployed: ${GREEN}$DEPLOYED${NC}"
echo "Failed deployments: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}[✓] All worker nodes deployed and operational${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Verify timers: systemctl list-timers | grep nas-"
    echo "2. Check sync: cat /opt/nas-sync/audit/.last-success"
    echo "3. View health: bash /opt/automation/scripts/healthcheck-worker-nas.sh"
else
    echo -e "${RED}[!] Some deployments failed. Check $DEPLOYMENT_LOG for details${NC}"
fi

# Cleanup
rm -f /tmp/deploy-nas-worker-*.sh

echo ""
echo "[SCALER] Deployment log available at: $DEPLOYMENT_LOG"
