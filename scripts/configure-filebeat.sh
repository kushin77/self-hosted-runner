#!/usr/bin/env bash
set -euo pipefail

# Idempotent Filebeat configuration deployer
# Usage: ./scripts/configure-filebeat.sh [worker_host] [elk_host]

WORKER_HOST="${1:-akushnir@192.168.168.42}"
ELK_HOST="${2:-elk.internal}"
LOCAL_TMP="/tmp/filebeat.yml"
REMOTE_CONF="/etc/filebeat/filebeat.yml"

echo "[1/4] Preparing Filebeat config for ELK output (host: $ELK_HOST)"
cat > "$LOCAL_TMP" <<EOF
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/*.log
      - /var/log/syslog

output.elasticsearch:
  hosts: ["http://$ELK_HOST:9200"]
  protocol: "http"

setup.kibana:
  host: "http://$ELK_HOST:5601"

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~
EOF

echo "[2/4] Uploading config to worker: $WORKER_HOST"
scp "$LOCAL_TMP" "$WORKER_HOST":/tmp/ || (echo "scp failed" && exit 1)

echo "[3/4] Installing config on worker and restarting filebeat"
# If ELK_HOST looks like an IP address, add an idempotent /etc/hosts entry mapping elk.internal
if [[ "$ELK_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[3a] ELK host looks like an IP; adding /etc/hosts entry on worker"
  ssh "$WORKER_HOST" "sudo sh -c 'grep -q "elk.internal" /etc/hosts || echo \"$ELK_HOST elk.internal\" >> /etc/hosts' || true"
fi

ssh "$WORKER_HOST" "sudo cp -f /tmp/filebeat.yml $REMOTE_CONF && sudo chown root:root $REMOTE_CONF && sudo chmod 640 $REMOTE_CONF && sudo systemctl restart filebeat && sudo systemctl enable filebeat"

echo "[4/4] Verifying filebeat status"
ssh "$WORKER_HOST" "systemctl is-active filebeat && systemctl status filebeat --no-pager | sed -n '1,5p'"

echo "Filebeat configuration deployed and service restarted on $WORKER_HOST"

exit 0
