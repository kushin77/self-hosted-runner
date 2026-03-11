#!/usr/bin/env bash
set -euo pipefail

# Automated hardened runner installer
# Provision a dedicated runner user, clone repo, configure credentials, and install cron job

REPO_URL="${REPO_URL:-https://github.com/kushin77/self-hosted-runner}"
RUNNER_HOME="${RUNNER_HOME:-/opt/runner}"
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_GROUP="${RUNNER_GROUP:-runner}"
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"
LOG_DIR="${LOG_DIR:-/var/log/chaos}"

echo "=== Hardened Runner Installer ==="
echo "Repo: $REPO_URL"
echo "Home: $RUNNER_HOME"
echo "User: $RUNNER_USER"
echo "Cron: $CRON_SCHEDULE"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)."
  exit 1
fi

# Create runner user
if ! id "$RUNNER_USER" &>/dev/null; then
  echo "Creating runner user: $RUNNER_USER"
  useradd -m -s /bin/bash "$RUNNER_USER" || echo "User already exists"
fi

# Create directories
echo "Creating directories..."
mkdir -p "$RUNNER_HOME" "$LOG_DIR"
chown "$RUNNER_USER:$RUNNER_GROUP" "$RUNNER_HOME" "$LOG_DIR"
chmod 750 "$RUNNER_HOME" "$LOG_DIR"

# Clone or update repo
if [ ! -d "$RUNNER_HOME/repo" ]; then
  echo "Cloning repository to $RUNNER_HOME/repo"
  sudo -u "$RUNNER_USER" git clone "$REPO_URL" "$RUNNER_HOME/repo"
else
  echo "Repository already exists; pulling latest..."
  sudo -u "$RUNNER_USER" -i bash -c "cd $RUNNER_HOME/repo && git pull origin main"
fi

# Install cron job
echo "Installing cron job..."
cron_cmd="/bin/bash -lc 'source $RUNNER_HOME/repo/scripts/ops/fetch_credentials.sh && $RUNNER_HOME/repo/scripts/testing/run-all-chaos-tests.sh' >> $LOG_DIR/orchestrator-\$(date +\\%F).log 2>&1"
cron_entry="$CRON_SCHEDULE $cron_cmd"

# Add cron entry if not already present
if ! crontab -u "$RUNNER_USER" -l 2>/dev/null | grep -q "run-all-chaos-tests.sh"; then
  echo "Adding cron entry for $RUNNER_USER"
  crontab -u "$RUNNER_USER" -l 2>/dev/null | cat - <(echo "$cron_entry") | crontab -u "$RUNNER_USER" -
else
  echo "Cron entry already present"
fi

# Harden SSH access for the runner user
echo "Hardening SSH access..."
mkdir -p "$RUNNER_HOME/.ssh"
chmod 700 "$RUNNER_HOME/.ssh"
chown "$RUNNER_USER:$RUNNER_GROUP" "$RUNNER_HOME/.ssh"

# Example: disable password auth for runner
# (Assumes key-based auth is already configured)
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config || echo "SSH hardening already configured"
systemctl reload sshd || echo "Could not reload sshd"

# Log setup summary
echo "=== Installation Summary ==="
echo "Runner user: $RUNNER_USER"
echo "Home directory: $RUNNER_HOME"
echo "Repo location: $RUNNER_HOME/repo"
echo "Log directory: $LOG_DIR"
echo "Cron schedule: $CRON_SCHEDULE"
echo ""
echo "Next steps:"
echo "1. Copy SSH public key to $RUNNER_HOME/.ssh/authorized_keys"
echo "2. Verify credentials are set up via GSM/Vault/KMS"
echo "3. Test cron manually: sudo -u $RUNNER_USER bash -c 'source $RUNNER_HOME/repo/scripts/ops/fetch_credentials.sh && $RUNNER_HOME/repo/scripts/testing/run-all-chaos-tests.sh'"
echo ""
echo "Installation complete!"
