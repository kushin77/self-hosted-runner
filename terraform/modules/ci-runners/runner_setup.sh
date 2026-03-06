#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Runner Setup Script
# Template for Terraform user_data

RUNNER_TOKEN="${runner_token}"
GITHUB_OWNER="${github_owner}"
GITHUB_REPO="${github_repo}"
RUNNER_DIR="${runner_dir}"
RUNNER_USER="ubuntu"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting runner setup..."

# Update system
apt-get update -qq
apt-get upgrade -y -qq

# Install dependencies
apt-get install -y -qq \
  curl wget git unzip jq \
  docker.io \
  build-essential \
  libssl-dev libffi-dev python3-dev

# Start Docker
systemctl start docker
systemctl enable docker
usermod -aG docker "$RUNNER_USER"

# Download and setup runner
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Determine runner version; allow override for reproducibility
RUNNER_VERSION=${RUNNER_VERSION:-}
if [ -z "$RUNNER_VERSION" ]; then
    RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//')
fi
RUNNER_ARCH=$([ "$(uname -m)" = "aarch64" ] && echo "arm64" || echo "x64")
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Downloading runner v${RUNNER_VERSION}..."

download_with_retries() {
    local url="$1" dest="$2" i
    for i in 1 2 3; do
        if curl -sSL --retry 3 --retry-delay 2 "$url" -o "$dest"; then
            return 0
        fi
        sleep $((i * 2))
    done
    return 1
}

if ! download_with_retries "$RUNNER_URL" runner.tar.gz; then
    echo "Failed to download runner from $RUNNER_URL" >&2
    exit 1
fi
tar xzf runner.tar.gz
rm runner.tar.gz

# Fix permissions
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# Configure runner
su - "$RUNNER_USER" -c "cd $RUNNER_DIR && ./config.sh --unattended \
  --url https://github.com/$GITHUB_OWNER/$GITHUB_REPO \
  --token $RUNNER_TOKEN \
  --name $(hostname)-runner \
  --labels 'self-hosted,$([ '$(nproc)' -gt 2 ] && echo 'high-mem' || echo 'standard')'"

# Install and enable systemd service
"$RUNNER_DIR/svc.sh" install "$RUNNER_USER"
"$RUNNER_DIR/svc.sh" start

# Install monitoring
mkdir -p /opt/runner-monitoring
cat > /opt/runner-monitoring/metrics.sh <<'METRICS_EOF'
#!/bin/bash
while true; do
  echo "# HELP runner_jobs_executed Total jobs executed"
  echo "# TYPE runner_jobs_executed counter" 
  grep -c "JobCompleted" "$RUNNER_DIR/_diag/Runner_*.log" 2>/dev/null | awk -F: '{sum+=$NF} END {print "runner_jobs_executed " sum}'
  sleep 60
done
METRICS_EOF

chmod +x /opt/runner-monitoring/metrics.sh

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner setup complete!"
