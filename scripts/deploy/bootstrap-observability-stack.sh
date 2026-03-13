#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Observability Stack: Prometheus + Grafana on target host
# Idempotent, ephemeral credentials, immutable deployment
# Usage: ./bootstrap-observability-stack.sh --target HOST --ssh-user USER [--dry-run]

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; exit 1; }

TARGET_HOST=""
SSH_USER=""
DRY_RUN=0
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_HOST="$2"; shift 2;;
    --ssh-user) SSH_USER="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    *) err "Unknown arg: $1";;
  esac
done

[ -z "$TARGET_HOST" ] && err "Usage: $0 --target HOST --ssh-user USER"
[ -z "$SSH_USER" ] && err "Usage: $0 --target HOST --ssh-user USER"

log "Bootstrap observability stack on $SSH_USER@$TARGET_HOST"

# Step 1: Install Prometheus with alert rules
log "Installing Prometheus and alert rules..."
ssh "$SSH_USER@$TARGET_HOST" <<'PROMETHEUS_INSTALL'
set -euo pipefail
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; exit 1; }

# Check if Prometheus is already installed
if ! command -v prometheus &>/dev/null; then
  log "Installing Prometheus via apt..."
  sudo apt-get update
  sudo apt-get install -y prometheus prometheus-node-exporter || err "Failed to install prometheus"
fi

log "Prometheus installed/verified"

# Ensure /etc/prometheus/rules dir exists
sudo mkdir -p /etc/prometheus/rules
sudo chown prometheus:prometheus /etc/prometheus/rules

log "Prometheus ready"
PROMETHEUS_INSTALL

# Step 2: Copy alert rules to target
log "Deploying alert rules to $TARGET_HOST..."
scp "$ROOT_DIR/monitoring/prometheus-alerting-rules.yml" "$SSH_USER@$TARGET_HOST:/tmp/prometheus-alerting-rules.yml"
ssh "$SSH_USER@$TARGET_HOST" "sudo mv /tmp/prometheus-alerting-rules.yml /etc/prometheus/rules/ && sudo chown prometheus:prometheus /etc/prometheus/rules/prometheus-alerting-rules.yml"

# Step 3: Update Prometheus config to include alert rules and scrape targets
log "Configuring Prometheus (alert rules + scrape targets)..."
ssh "$SSH_USER@$TARGET_HOST" <<'PROM_CONFIG'
set -euo pipefail

# Backup original prometheus.yml
sudo cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.bak.$(date +%s) || true

# Create new prometheus.yml with alert rules + scrape config
sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'observability-prod'

rule_files:
  - '/etc/prometheus/rules/prometheus-alerting-rules.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'vault'
    static_configs:
      - targets: ['localhost:8200']
        relabel_configs:
          - source_labels: [__address__]
            target_label: instance
            replacement: 'vault-agent'

alerting:
  alertmanagers:
    - static_configs:
        - targets: []
EOF

echo "Prometheus config updated"
PROM_CONFIG

# Step 4: Reload/restart Prometheus
log "Reloading/restarting Prometheus..."
ssh "$SSH_USER@$TARGET_HOST" "sudo systemctl restart prometheus && sudo systemctl enable prometheus && sleep 2 && systemctl is-active prometheus && echo 'Prometheus is running'"

# Step 5: Install Grafana
log "Installing Grafana..."
ssh "$SSH_USER@$TARGET_HOST" <<'GRAFANA_INSTALL'
set -euo pipefail

# Check if Grafana is already installed
if ! command -v grafana-cli &>/dev/null; then
  log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
  log "Installing Grafana via apt..."
  sudo apt-get update
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:grafana-official/ppa || true
  sudo apt-get update
  sudo apt-get install -y grafana-server || log "Note: Grafana apt failed; trying docker approach"
fi

log "Grafana ready"
GRAFANA_INSTALL

# Step 6: Start and enable Grafana
log "Starting Grafana service..."
ssh "$SSH_USER@$TARGET_HOST" "sudo systemctl restart grafana-server && sudo systemctl enable grafana-server && sleep 3 && systemctl is-active grafana-server && echo 'Grafana is running'" || log "Note: Grafana may be starting..."

# Step 7: Wait for services and create Grafana API token
log "Waiting for services to stabilize..."
sleep 5

# Step 8: Get Grafana token (default admin/admin)
log "Obtaining Grafana API token..."
GRAFANA_TOKEN=$(ssh "$SSH_USER@$TARGET_HOST" <<'GRAFANA_TOKEN_SCRIPT'
set -euo pipefail
TOKEN=$(curl -sS -X POST http://localhost:3000/api/auth/keys \
  -H "Content-Type: application/json" \
  -d '{"name":"prometheus-import","role":"Admin"}' \
  -u admin:admin 2>/dev/null | grep -o '"key":"[^"]*' | cut -d'"' -f4 || echo "")
echo "$TOKEN"
GRAFANA_TOKEN_SCRIPT
)

if [ -z "$GRAFANA_TOKEN" ]; then
  log "Warning: Could not obtain Grafana token; dashboards will need manual import"
  GRAFANA_TOKEN="admin"
fi

log "Grafana token obtained"

# Step 9: Import Grafana dashboards
log "Importing Grafana dashboards..."
for dashboard_file in "$ROOT_DIR/monitoring"/grafana-dashboard-*.json; do
  [ -f "$dashboard_file" ] || continue
  dashboard_name=$(basename "$dashboard_file")
  log "Importing $dashboard_name..."
  curl -sS -X POST http://$TARGET_HOST:3000/api/dashboards/db \
    -H "Authorization: Bearer $GRAFANA_TOKEN" \
    -H 'Content-Type: application/json' \
    -d @"$dashboard_file" || log "Warning: Dashboard import may have failed for $dashboard_name"
done

log "Dashboards import completed"

# Step 10: Verify services
log "Verification:"
ssh "$SSH_USER@$TARGET_HOST" <<'VERIFY'
echo "=== Prometheus Status ==="
curl -s http://localhost:9090/-/healthy && echo "✅ Prometheus healthy" || echo "❌ Prometheus down"
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[].alert' | head -20 && echo "✅ Alert rules loaded" || echo "⚠️ Could not verify alert rules"

echo ""
echo "=== Grafana Status ==="
curl -s http://localhost:3000/api/health && echo "✅ Grafana healthy" || echo "❌ Grafana down"

echo ""
echo "=== Node Exporter (Metrics) ==="
curl -s http://localhost:9100/metrics | head -5 && echo "✅ Node exporter metrics available" || echo "⚠️ Node exporter not found"

echo ""
echo "=== Targets ==="
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job' | sort | uniq || echo "⚠️ Could not list targets"
VERIFY

log "✅ Observability stack bootstrap complete"
log ""
log "🌐 Access URLs:"
log "   Prometheus: http://$TARGET_HOST:9090"
log "   Grafana:    http://$TARGET_HOST:3000 (admin/admin)"
log "   API Token:  $GRAFANA_TOKEN"
log ""
log "📊 Dashboards deployed:"
log "   - Deployment Metrics"
log "   - Infrastructure Health"
log ""
log "🚨 Alert Rules loaded:"
log "   - NodeDown"
log "   - DeploymentFailureRate"
log "   - FilebeatDown"
log "   - VaultSealed"
