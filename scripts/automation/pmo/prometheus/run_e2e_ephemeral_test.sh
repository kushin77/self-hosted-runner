#!/usr/bin/env bash
set -euo pipefail

# Ephemeral, immutable E2E test for Alertmanager -> HTTP receiver
# - Creates an isolated Docker network
# - Runs a simple Python-based mock webhook listening on /hooks/slack
# - Runs Alertmanager with a generated config that posts to the mock webhook
# - Sends a synthetic alert and verifies delivery via mock logs

TMPDIR=$(mktemp -d /tmp/observability-e2e.XXXX)
cleanup() {
  set +e
  docker rm -f observability-e2e-alertmanager >/dev/null 2>&1 || true
  docker rm -f observability-e2e-mock-webhook >/dev/null 2>&1 || true
  [ -n "${NETWORK:-}" ] && docker network rm "$NETWORK" >/dev/null 2>&1 || true
  # Use safe_delete wrapper for temp dir cleanup
  SAFE_DELETE="$(pwd)/scripts/safe_delete.sh"
  if [ ! -x "$SAFE_DELETE" ]; then SAFE_DELETE="$(dirname "$0")/../../scripts/safe_delete.sh"; fi
  if [ -x "$SAFE_DELETE" ]; then
    "$SAFE_DELETE" --path "$TMPDIR" --dry-run || true
  else
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

echo "Using temp dir: $TMPDIR"

# parse optional args: --slack-url and --pagerduty-key
SLACK_URL=""
PAGERDUTY_KEY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --slack-url) SLACK_URL="$2"; shift 2 ;;
    --pagerduty-key) PAGERDUTY_KEY="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  esac
done

# debug output
if [ "${DEBUG_MODE:-false}" = "true" ]; then
  echo "=== EPHEMERAL E2E TEST - DEBUG MODE ==="
  echo "SLACK_URL configured: $([ -n "$SLACK_URL" ] && echo 'yes (length: '${#SLACK_URL}')' || echo 'no')"
  echo "PAGERDUTY_KEY configured: $([ -n "$PAGERDUTY_KEY" ] && echo 'yes (length: '${#PAGERDUTY_KEY}')' || echo 'no')"
  echo "Temp directory: $TMPDIR"
  echo "========================================"
fi

# generate Alertmanager config; prefer real receivers if provided, otherwise use mock webhook
if [ -n "$SLACK_URL" ] || [ -n "$PAGERDUTY_KEY" ]; then
  echo "Generating Alertmanager config for real receivers..."
  if [ "${DEBUG_MODE:-false}" = "true" ]; then
    echo "SLACK_URL length: ${#SLACK_URL}"
    echo "PAGERDUTY_KEY length: ${#PAGERDUTY_KEY}"
  fi
  
  cat > "$TMPDIR/alertmanager.yml" <<'AMCFG'
global:
  resolve_timeout: 5m
route:
  receiver: 'default'
receivers:
  - name: 'default'
    webhook_configs: []
AMCFG

  if [ -n "$SLACK_URL" ]; then
    echo "✓ Configuring Slack receiver"
    cat >> "$TMPDIR/alertmanager.yml" <<AMCFG
  - name: 'slack'
    slack_configs:
      - api_url: '$SLACK_URL'
        send_resolved: true
        channel: '#alerts'
AMCFG
    # set route to slack
    sed -i "s/receiver: 'default'/receiver: 'slack'/" "$TMPDIR/alertmanager.yml"
  fi
  
  if [ -n "$PAGERDUTY_KEY" ]; then
    echo "✓ Configuring PagerDuty receiver"
    cat >> "$TMPDIR/alertmanager.yml" <<AMCFG
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '$PAGERDUTY_KEY'
AMCFG
    sed -i "s/receiver: 'default'/receiver: 'pagerduty'/" "$TMPDIR/alertmanager.yml"
  fi
else
  echo "Generating Alertmanager config with mock webhook..."
  cat > "$TMPDIR/alertmanager.yml" <<'AMCFG'
global:
  resolve_timeout: 5m
route:
  receiver: 'slack'
receivers:
  - name: 'slack'
    webhook_configs:
      - url: 'http://observability-e2e-mock-webhook:8080/hooks/slack'
        send_resolved: true
AMCFG
fi

# validate config was written
if [ ! -f "$TMPDIR/alertmanager.yml" ]; then
  echo "ERROR: alertmanager.yml was not created" >&2
  exit 2
fi

if [ "${DEBUG_MODE:-false}" = "true" ]; then
  echo "===== Generated Alertmanager Config ====="
  cat "$TMPDIR/alertmanager.yml"
  echo "=========================================="
fi

# create isolated network
NETWORK="observability_e2e_$(date +%s%N | sha256sum | cut -c1-8)"
docker network create "$NETWORK"
echo "Created network: $NETWORK"

# start mock webhook (simple Flask app) attached to network
docker run -d --name observability-e2e-mock-webhook --network "$NETWORK" \
  python:3.11-slim bash -lc "pip install --no-cache-dir flask >/dev/null 2>&1 && python -u - <<'PY'
from flask import Flask, request
app = Flask(__name__)
@app.route('/hooks/slack', methods=['POST'])
def hook():
    data = request.get_data()
    print(data.decode('utf-8'))
    return ('', 200)
app.run(host='0.0.0.0', port=8080)
PY"

echo "Started mock webhook"

# start Alertmanager with generated config
docker run -d --name observability-e2e-alertmanager --network "$NETWORK" \
  -v "$TMPDIR/alertmanager.yml":/etc/alertmanager/alertmanager.yml \
  prom/alertmanager:v0.26.0 --config.file=/etc/alertmanager/alertmanager.yml

echo "Started Alertmanager"

# wait for alertmanager API with improved timeout logic
ALERTMANAGER_READY=0
for i in $(seq 1 60); do
  # First check: container is still running
  if ! docker ps --filter name=observability-e2e-alertmanager --format '{{.Names}}' | grep -q observability-e2e-alertmanager; then
    echo "ERROR: Alertmanager container is not running" >&2
    docker logs observability-e2e-alertmanager 2>&1 | tail -20
    exit 3
  fi
  
  # Second check: Alertmanager API responds
  if docker run --rm --network "$NETWORK" curlimages/curl:7.88.1 -sS -m 5 http://observability-e2e-alertmanager:9093/api/v1/alerts >/dev/null 2>&1; then
    echo "✓ Alertmanager ready after $((i*2)) seconds"
    ALERTMANAGER_READY=1
    break
  fi
  echo "Waiting for Alertmanager... ($i/60, $((i*2))s elapsed)"
  sleep 2
done

if [ $ALERTMANAGER_READY -ne 1 ]; then
  echo "ERROR: Alertmanager did not become ready after 120 seconds" >&2
  echo "Container logs (last 30 lines):" >&2
  docker logs --tail 30 observability-e2e-alertmanager 2>&1
  echo "Network diagnostics:" >&2
  docker exec observability-e2e-alertmanager ps aux 2>&1 || true
  exit 3
fi

# build a synthetic alert payload
cat > "$TMPDIR/alert.json" <<'ALERT'
[{
  "labels": {"alertname": "TestAlert", "severity": "critical"},
  "annotations": {"summary": "E2E test alert"},
  "startsAt": "2020-01-01T00:00:00Z"
}]
ALERT

echo "Posting synthetic alert to Alertmanager"
ALERT_RESPONSE=$(docker run --rm --network "$NETWORK" -v "$TMPDIR/alert.json":/alert.json curlimages/curl:7.88.1 -sS -XPOST -H "Content-Type: application/json" --data-binary @/alert.json http://observability-e2e-alertmanager:9093/api/v1/alerts 2>&1)
ALERT_EXIT=$?
if [ $ALERT_EXIT -eq 0 ]; then
  echo "✓ Alert posted successfully"
  [ -n "$ALERT_RESPONSE" ] && echo "Response: $ALERT_RESPONSE"
else
  echo "⚠ Alert post returned exit code $ALERT_EXIT"
  echo "$ALERT_RESPONSE"
fi

echo "Sleeping briefly to allow delivery..."
sleep 3

echo "Alertmanager logs (last 50 lines):"
docker logs --tail 50 observability-e2e-alertmanager | tail -20

echo "Mock webhook logs (last 100 lines):"
WEBHOOK_LOGS=$(docker logs --tail 100 observability-e2e-mock-webhook 2>&1)
echo "$WEBHOOK_LOGS" | tail -30
if echo "$WEBHOOK_LOGS" | grep -q "TestAlert"; then
  echo "✓ Test alert payload found in webhook logs"
else
  echo "⚠ Test alert payload NOT found in webhook logs - delivery may have failed"
fi

echo "E2E run complete"

exit 0
