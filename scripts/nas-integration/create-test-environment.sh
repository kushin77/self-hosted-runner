#!/bin/bash
# NAS Staging/Test Environment Generator
# Creates template environments for testing configurations before production deployment
# Usage: ./create-test-environment.sh <environment_name> <base_node_ip>

set -e

ENV_NAME="${1:-staging}"
BASE_NODE_IP="${2:-192.168.168.50}"

if [ "$ENV_NAME" = "" ]; then
    echo "Usage: $0 <environment_name> <node_ip>"
    echo "Example: $0 staging 192.168.168.50"
    exit 1
fi

cat > /tmp/create-test-env-${ENV_NAME}.sh << 'TEST_ENV_SETUP'
#!/bin/bash
set -e

ENV_NAME=$1
NODE_IP=$2

echo "[TEST-ENV] Creating $ENV_NAME environment on $NODE_IP..."

# Create environment-specific directories
mkdir -p /opt/nas-test-${ENV_NAME}/{iac,configs,credentials,audit}
chmod 700 /opt/nas-test-${ENV_NAME}/credentials

# Copy scripts with environment prefix
cp /opt/automation/scripts/worker-node-nas-sync.sh /opt/automation/scripts/test-${ENV_NAME}-sync.sh
cp /opt/automation/scripts/healthcheck-worker-nas.sh /opt/automation/scripts/test-${ENV_NAME}-health.sh

# Create environment-specific systemd service
sudo tee /etc/systemd/system/nas-test-${ENV_NAME}.service > /dev/null << EOF
[Unit]
Description=NAS Test Environment Sync - ${ENV_NAME}
After=network.target

[Service]
Type=oneshot
User=automation
ExecStart=/opt/automation/scripts/test-${ENV_NAME}-sync.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create timer with different interval (15 min for testing)
sudo tee /etc/systemd/system/nas-test-${ENV_NAME}.timer > /dev/null << EOF
[Unit]
Description=NAS Test Environment Sync Timer - ${ENV_NAME}

[Timer]
OnBootSec=30sec
OnUnitActiveSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable nas-test-${ENV_NAME}.timer
sudo systemctl start nas-test-${ENV_NAME}.timer

echo "[TEST-ENV] Environment $ENV_NAME created successfully"
TEST_ENV_SETUP

chmod +x /tmp/create-test-env-${ENV_NAME}.sh

# Deploy to node
ssh -o ConnectTimeout=5 "automation@${BASE_NODE_IP}" "bash -s ${ENV_NAME} ${BASE_NODE_IP}" < /tmp/create-test-env-${ENV_NAME}.sh

echo "✓ Test environment '${ENV_NAME}' created on ${BASE_NODE_IP}"
echo "  Location: /opt/nas-test-${ENV_NAME}/"
echo "  Sync timer: nas-test-${ENV_NAME}.timer (15 min interval)"
echo "  Verification: systemctl status nas-test-${ENV_NAME}.timer"

rm -f /tmp/create-test-env-${ENV_NAME}.sh
