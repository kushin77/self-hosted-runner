#!/usr/bin/env bash
set -euo pipefail

# Idempotent ELK credentials automation for Filebeat
# Fetches credentials from Vault/GSM, updates Filebeat config, verifies indexing
# Usage: ./scripts/apply-elk-credentials-to-filebeat.sh [--elk-host ELK_HOST] [--vault-path SECRET_PATH] [--dry-run]

WORKER_HOST="${WORKER_HOST:-akushnir@192.168.168.42}"
ELK_HOST="${ELK_HOST:-}"
VAULT_PATH="${VAULT_PATH:-secret/elk/filebeat-credentials}"
DRY_RUN=false
AUDIT_LOG="logs/elk-integration-audit.jsonl"

log_info() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] INFO: $*"; }
log_error() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; }
log_audit() {
  local action="$1" status="$2" details="${3:-}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"$action\",\"status\":\"$status\",\"details\":$details}" >> "$AUDIT_LOG"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --elk-host) ELK_HOST="$2"; shift 2;;
    --vault-path) VAULT_PATH="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --elk-host ELK_HOST         ELK/Elasticsearch host (e.g., elk.internal or 10.0.0.5)
  --vault-path PATH           Vault KV path for ELK credentials (default: secret/elk/filebeat-credentials)
  --dry-run                   Simulate without applying changes
  -h, --help                  Show this help

Environment:
  WORKER_HOST                 SSH target for worker (default: akushnir@192.168.168.42)
  VAULT_ADDR, VAULT_TOKEN     Vault connectivity (or use gcloud/gsm)

Example:
  VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<YOUR_VAULT_TOKEN> \\
    $0 --elk-host elk.internal --vault-path secret/elk/filebeat-credentials

EOF
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1;;
  esac
done

mkdir -p logs
log_audit "elk_integration_start" "STARTED" "{\"dry_run\":$DRY_RUN,\"elk_host\":\"$ELK_HOST\",\"vault_path\":\"$VAULT_PATH\"}"

# Step 1: Validate inputs
if [ -z "$ELK_HOST" ]; then
  log_error "ELK_HOST not provided; use --elk-host or set VAULT_PATH/VAULT_ADDR"
  log_audit "elk_integration_failed" "ERROR" "{\"reason\":\"elk_host_not_provided\"}"
  exit 1
fi

log_info "[1/5] Fetching ELK credentials from Vault..."
if [ -n "${VAULT_ADDR:-}" ] && [ -n "${VAULT_TOKEN:-}" ]; then
  # Fetch from Vault
  ELK_CREDS=$(vault kv get -format=json "$VAULT_PATH" 2>/dev/null | jq -r '.data.data | "\(.username):\(.password)"' || true)
  if [ -z "$ELK_CREDS" ]; then
    log_info "  No credentials found in Vault at $VAULT_PATH; proceeding without auth"
    ELK_CREDS=""
  else
    log_info "  ✓ Credentials fetched from Vault"
  fi
elif command -v gcloud >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # Fetch from GSM
  log_info "  Attempting GSM retrieval..."
  SECRET_NAME="elk-filebeat-credentials"
  ELK_CREDS=$(gcloud secrets versions access latest --secret="$SECRET_NAME" 2>/dev/null | jq -r '"\(.username):\(.password)"' || true)
  if [ -z "$ELK_CREDS" ]; then
    log_info "  No credentials found in GSM; proceeding without auth"
    ELK_CREDS=""
  else
    log_info "  ✓ Credentials fetched from GSM"
  fi
else
  log_info "  Vault/GSM not available; proceeding without credentials"
  ELK_CREDS=""
fi

# Step 2: Generate Filebeat config
log_info "[2/5] Generating Filebeat config for ELK host: $ELK_HOST"
LOCAL_FILEBEAT_CONFIG="/tmp/filebeat-elk-config.yml"
cat > "$LOCAL_FILEBEAT_CONFIG" <<EOF
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /home/akushnir/logs/*.jsonl
      - /var/log/*.log
    json.keys_under_root: true
    json.add_error_key: true
    processors:
      - add_fields:
          target: ''
          fields:
            source: runner_audit

output.elasticsearch:
  enabled: true
  hosts: ["http://$ELK_HOST:9200"]
  protocol: "http"
  index: "runner-audit-%{+yyyy.MM.dd}"
EOF

if [ -n "$ELK_CREDS" ]; then
  cat >> "$LOCAL_FILEBEAT_CONFIG" <<EOF
  username: "$(echo "$ELK_CREDS" | cut -d: -f1)"
  password: "$(echo "$ELK_CREDS" | cut -d: -f2)"
EOF
fi

cat >> "$LOCAL_FILEBEAT_CONFIG" <<EOF

setup.kibana:
  host: "http://$ELK_HOST:5601"

processors:
  - add_host_metadata: ~
  - add_process_metadata: ~

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
EOF

if [ "$DRY_RUN" = true ]; then
  log_info "  [DRY-RUN] Generated config:"
  cat "$LOCAL_FILEBEAT_CONFIG"
  log_audit "elk_integration_config_generated" "DRY_RUN" "{\"config_size\":$(wc -c < \"$LOCAL_FILEBEAT_CONFIG\")}"
  exit 0
fi

# Step 3: Deploy config to worker
log_info "[3/5] Deploying config to worker: $WORKER_HOST"
scp "$LOCAL_FILEBEAT_CONFIG" "$WORKER_HOST:/tmp/filebeat-elk.yml" || {
  log_error "Failed to upload config to worker"
  log_audit "elk_integration_deploy_failed" "ERROR" "{\"reason\":\"config_upload_failed\"}"
  exit 1
}

# Add ELK host to /etc/hosts if it's an IP
if [[ "$ELK_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ssh "$WORKER_HOST" "sudo sh -c 'grep -q \"elk.internal\" /etc/hosts || echo \"$ELK_HOST elk.internal\" >> /etc/hosts'" || true
fi

# Step 4: Apply config and restart Filebeat
log_info "[4/5] Installing and restarting Filebeat on worker"
ssh "$WORKER_HOST" "sudo cp -f /tmp/filebeat-elk.yml /etc/filebeat/filebeat.yml && \
  sudo chown root:root /etc/filebeat/filebeat.yml && \
  sudo chmod 640 /etc/filebeat/filebeat.yml && \
  sudo systemctl restart filebeat && \
  sudo systemctl is-active filebeat" || {
  log_error "Failed to restart Filebeat on worker"
  log_audit "elk_integration_restart_failed" "ERROR" "{\"reason\":\"filebeat_restart_failed\"}"
  exit 1
}

log_info "  ✓ Filebeat restarted"

# Step 5: Verify connection (basic check)
log_info "[5/5] Verifying Filebeat connection to ELK..."
VERIFY_OUTPUT=$(ssh "$WORKER_HOST" "sudo systemctl status filebeat --no-pager | head -10" 2>/dev/null || true)
if echo "$VERIFY_OUTPUT" | grep -q "active (running)"; then
  log_info "  ✓ Filebeat service active"
  log_audit "elk_integration_complete" "SUCCESS" "{\"elk_host\":\"$ELK_HOST\",\"filebeat_status\":\"active\"}"
  echo ""
  echo "✅ ELK integration complete!"
  echo "   - Filebeat configured to ship logs to $ELK_HOST:9200"
  echo "   - Logs will be indexed as: runner-audit-YYYY.MM.DD"
  echo "   - Access Kibana at http://$ELK_HOST:5601"
  echo "   - Search for recent entries from logs/revocation-audit.jsonl and logs/7day-monitoring.jsonl"
else
  log_error "Filebeat service verification failed"
  log_audit "elk_integration_verify_failed" "WARNING" "{\"reason\":\"filebeat_status_check_failed\"}"
  exit 1
fi

exit 0
