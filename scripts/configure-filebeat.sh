#!/usr/bin/env bash
set -euo pipefail

# Idempotent Filebeat configuration deployer
# Usage: ./scripts/configure-filebeat.sh [worker_host]

WORKER_HOST="${1:-akushnir@192.168.168.42}"
LOCAL_TMP="/tmp/filebeat.yml"
REMOTE_CONF="/etc/filebeat/filebeat.yml"

echo "[1/4] Preparing Filebeat config for ELK output"
cat > "$LOCAL_TMP" <<'EOF'
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/*.log
      - /var/log/syslog

output.elasticsearch:
  hosts: ["http://elk.internal:9200"]
  protocol: "http"

setup.kibana:
  host: "http://elk.internal:5601"

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
EOF

echo "[2/4] Uploading config to worker: $WORKER_HOST"
scp "$LOCAL_TMP" "$WORKER_HOST":/tmp/ || (echo "scp failed" && exit 1)

echo "[3/4] Installing config on worker and restarting filebeat"
ssh "$WORKER_HOST" "sudo cp -f /tmp/filebeat.yml $REMOTE_CONF && sudo chown root:root $REMOTE_CONF && sudo chmod 640 $REMOTE_CONF && sudo systemctl restart filebeat && sudo systemctl enable filebeat"

echo "[4/4] Verifying filebeat status"
ssh "$WORKER_HOST" "systemctl is-active filebeat && systemctl status filebeat --no-pager | sed -n '1,5p'"

echo "Filebeat configuration deployed and service restarted on $WORKER_HOST"

exit 0
