#!/bin/bash
################################################################################
# PHASE 5 - STAGE 4: ACTIVATE SYSTEMD TIMERS
# Setup systemd services and timers for automated NAS operations
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SYSTEMD_DIR="/etc/systemd/system"

echo ""
echo "================================================================================"
echo "PHASE 5 - STAGE 4: ACTIVATE SYSTEMD TIMERS (T+21-25 min)"
echo "================================================================================"
echo ""

# Check if running with sufficient privileges
if [[ $EUID -ne 0 ]]; then
  echo "[!] ERROR: This script must be run as root (use sudo)"
  exit 1
fi

echo "[*] Creating/updating systemd service files..."
echo ""

# Create svc-git-key service (credential refresh from GSM)
echo "[*] Creating svc-git-key.service (credential refresh from GSM)..."
cat > "$SYSTEMD_DIR/svc-git-key.service" << 'EOFSERVICE'
[Unit]
Description=Fetch svc-git SSH key from GSM and setup authentication
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=svc-git
Environment="HOME=/home/svc-git"
ExecStart=/bin/bash -c 'mkdir -p /home/svc-git/.ssh && \
  gcloud secrets versions access latest --secret=svc-git-ssh-key > /home/svc-git/.ssh/id_ed25519 && \
  chmod 600 /home/svc-git/.ssh/id_ed25519 && \
  ssh-keyscan -t ed25519 github.com >> /home/svc-git/.ssh/known_hosts 2>/dev/null || true'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE
echo "  ✓ svc-git-key.service created"

# Create NAS stress test service
echo "[*] Creating nas-stress-test.service..."
cat > "$SYSTEMD_DIR/nas-stress-test.service" << 'EOFSERVICE'
[Unit]
Description=NAS Infrastructure Stress Test and Monitoring
After=svc-git-key.service network-online.target
Wants=network-online.target
Requires=svc-git-key.service

[Service]
Type=oneshot
User=automation
WorkingDirectory=/home/automation
ExecStart=/bin/bash /home/akushnir/self-hosted-runner/deploy-nas-stress-tests.sh --quick
StandardOutput=journal
StandardError=journal
PrivateTmp=yes
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOFSERVICE
echo "  ✓ nas-stress-test.service created"

# Create NAS stress test timer (daily)
echo "[*] Creating nas-stress-test.timer (daily @ 2:00 AM UTC)..."
cat > "$SYSTEMD_DIR/nas-stress-test.timer" << 'EOFTIMER'
[Unit]
Description=Daily NAS Stress Test Timer
Requires=nas-stress-test.service

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOFTIMER
echo "  ✓ nas-stress-test.timer created"

# Create NAS stress test weekly service
echo "[*] Creating nas-stress-test-weekly.service..."
cat > "$SYSTEMD_DIR/nas-stress-test-weekly.service" << 'EOFSERVICE'
[Unit]
Description=Weekly Comprehensive NAS Stress Test
After=svc-git-key.service network-online.target
Wants=network-online.target
Requires=svc-git-key.service

[Service]
Type=oneshot
User=automation
WorkingDirectory=/home/automation
ExecStart=/bin/bash /home/akushnir/self-hosted-runner/deploy-nas-stress-tests.sh --medium
StandardOutput=journal
StandardError=journal
PrivateTmp=yes
TimeoutStartSec=1200

[Install]
WantedBy=multi-user.target
EOFSERVICE
echo "  ✓ nas-stress-test-weekly.service created"

# Create NAS stress test weekly timer
echo "[*] Creating nas-stress-test-weekly.timer (weekly @ Sunday 3:00 AM UTC)..."
cat > "$SYSTEMD_DIR/nas-stress-test-weekly.timer" << 'EOFTIMER'
[Unit]
Description=Weekly Comprehensive NAS Stress Test Timer
Requires=nas-stress-test-weekly.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOFTIMER
echo "  ✓ nas-stress-test-weekly.timer created"

echo ""
echo "[*] Reloading systemd configuration..."
systemctl daemon-reload
echo "  ✓ Daemon reloaded"

echo ""
echo "[*] Enabling and starting services..."
echo ""

# Enable and start credential service
echo "[*] svc-git-key.service:"
systemctl enable svc-git-key.service
systemctl start svc-git-key.service
systemctl status svc-git-key.service --no-pager | head -10
echo ""

# Enable and start daily timer
echo "[*] nas-stress-test.timer (daily @ 2:00 AM UTC):"
systemctl enable nas-stress-test.timer
systemctl start nas-stress-test.timer
systemctl status nas-stress-test.timer --no-pager | head -10
echo ""

# Enable and start weekly timer
echo "[*] nas-stress-test-weekly.timer (weekly @ Sunday 3:00 AM UTC):"
systemctl enable nas-stress-test-weekly.timer
systemctl start nas-stress-test-weekly.timer
systemctl status nas-stress-test-weekly.timer --no-pager | head -10
echo ""

echo "[*] Systemd timers configured:"
echo ""
systemctl list-timers nas-stress-test* --no-pager
echo ""

echo "================================================================================"
echo "✅ STAGE 4 COMPLETE - All systemd timers activated"
echo "================================================================================"
echo ""
echo "Summary:"
echo "  • svc-git-key.service: Credential refresh from GSM"
echo "  • nas-stress-test.timer: Daily @ 2:00 AM UTC"
echo "  • nas-stress-test-weekly.timer: Weekly @ Sunday 3:00 AM UTC"
echo ""
echo "Next: Proceed to STAGE 5 (Verification & Monitoring)"
