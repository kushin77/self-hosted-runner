#!/bin/bash
set -euo pipefail

# Install and configure Datadog Agent for deployment audit log shipping
# Usage: sudo bash install-datadog-agent.sh <DATADOG_API_KEY> [DATADOG_SITE]
# Example: sudo bash install-datadog-agent.sh abcd1234efgh5678ijkl9012mnop3456 datadoghq.com

log(){ echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $@"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root (or via sudo)" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <DATADOG_API_KEY> [DATADOG_SITE]" >&2
  echo "Example: $0 abcd1234efgh5678ijkl9012mnop3456 datadoghq.com" >&2
  exit 1
fi

API_KEY="$1"
SITE="${2:-datadoghq.com}"

log "Installing Datadog Agent"

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS="unknown"
fi

case "$OS" in
  ubuntu|debian)
    log "Detected Debian/Ubuntu; installing via APT"
    apt-get update -y
    apt-get install -y curl software-properties-common
    
    # Add Datadog APT repo
    curl -fsSL https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public | apt-key add -
    echo "deb https://apt.datadoghq.com/ stable 7" > /etc/apt/sources.list.d/datadog.list
    apt-get update -y
    apt-get install -y datadog-agent
    ;;
  *)
    log "Unsupported OS: $OS"
    exit 1
    ;;
esac

log "Configuring Datadog Agent for deployment audit logs..."

# Create datadog-agent config
cat > /etc/datadog-agent/datadog.yaml <<EOF
hostname: $(hostname -f)
api_key: $API_KEY
site: $SITE
dd_url: https://api.$SITE
log_level: info
apm_enabled: false

# Tags applied to all metrics/logs
tags:
  - "env:production"
  - "service:deployment"
  - "host:$(hostname -f)"
EOF

# Create custom check for deployment audit logs
mkdir -p /etc/datadog-agent/conf.d/custom_logs.d
cat > /etc/datadog-agent/conf.d/custom_logs.d/conf.yaml <<'EOF'
logs:
  - type: file
    path: /run/app-deployment-state/deployed.state
    service: deployment-audit
    source: custom
    tags:
      - "env:production"
      - "log_type:deployment_audit"
EOF

log "Starting Datadog Agent service..."
systemctl enable datadog-agent
systemctl restart datadog-agent

# Verify
sleep 3
if systemctl is-active datadog-agent >/dev/null; then
  log "✓ Datadog Agent started successfully"
  log "Audit logs will be shipped to: https://app.$SITE/logs"
else
  log "✗ Datadog Agent failed to start"
  systemctl status datadog-agent --no-pager || true
  exit 1
fi

log "Datadog Agent installation complete"
exit 0
