#!/usr/bin/env bash
set -euo pipefail

WORKER=akushnir@192.168.168.42
LOG=/home/akushnir/self-hosted-runner/logs/integration-test-$(date -u +%Y%m%d_%H%M%S).log
mkdir -p $(dirname "$LOG")

echo "Integration test started: $(date -u)" | tee "$LOG"

echo "[1] Service statuses on worker" | tee -a "$LOG"
ssh $WORKER 'systemctl status vault-agent node_exporter filebeat --no-pager | sed -n "1,80p"' | tee -a "$LOG"

echo "[2] Prometheus metrics endpoint" | tee -a "$LOG"
ssh $WORKER 'curl -sSf http://127.0.0.1:9100/metrics | head -n 20' >> "$LOG" 2>&1 || echo "node_exporter metrics not reachable" | tee -a "$LOG"

echo "[3] Test Vault credential retrieval via helper" | tee -a "$LOG"
ssh $WORKER '~/.runner/bin/get-vault-secret.sh runner/aws-credentials' >> "$LOG" 2>&1 || echo "Vault credential retrieval failed" | tee -a "$LOG"

echo "[4] Verify Filebeat is shipping (local log)" | tee -a "$LOG"
ssh $WORKER 'sudo systemctl status filebeat --no-pager | sed -n "1,20p"' >> "$LOG" 2>&1

echo "Integration test completed: $(date -u)" | tee -a "$LOG"

cat "$LOG"

exit 0
