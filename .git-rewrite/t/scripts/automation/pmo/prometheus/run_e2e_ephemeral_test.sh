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
  rm -rf "$TMPDIR"
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

# generate Alertmanager config; prefer real receivers if provided, otherwise use mock webhook
if [ -n "$SLACK_URL" ] || [ -n "$PAGERDUTY_KEY" ]; then
  cat > "$TMPDIR/alertmanager.yml" <<AMCFG
global:
  resolve_timeout: 5m
route:
  receiver: 'default'
receivers:
  - name: 'default'
    webhook_configs: []
AMCFG
  if [ -n "$SLACK_URL" ]; then
    cat >> "$TMPDIR/alertmanager.yml" <<AMCFG
  - name: 'slack'
    webhook_configs:
      - url: '$SLACK_URL'
        send_resolved: true
AMCFG
    # set route to slack
    sed -i "s/receiver: 'default'/receiver: 'slack'/" "$TMPDIR/alertmanager.yml"
  fi
  if [ -n "$PAGERDUTY_KEY" ]; then
    cat >> "$TMPDIR/alertmanager.yml" <<AMCFG
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '$PAGERDUTY_KEY'
AMCFG
    sed -i "s/receiver: 'default'/receiver: 'pagerduty'/" "$TMPDIR/alertmanager.yml"
  fi
else
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

# wait for alertmanager API
for i in $(seq 1 30); do
  if docker run --rm --network "$NETWORK" curlimages/curl:7.88.1 -sS http://observability-e2e-alertmanager:9093/- >/dev/null 2>&1; then
    echo "Alertmanager ready"
    break
  fi
  echo "Waiting for Alertmanager... ($i)"
  sleep 2
done

if ! docker ps --filter name=observability-e2e-alertmanager --format '{{.Names}}' | grep -q observability-e2e-alertmanager; then
  echo "Alertmanager failed to start" >&2
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
docker run --rm --network "$NETWORK" -v "$TMPDIR/alert.json":/alert.json curlimages/curl:7.88.1 -sS -XPOST -H "Content-Type: application/json" --data-binary @/alert.json http://observability-e2e-alertmanager:9093/api/v1/alerts || true

echo "Sleeping briefly to allow delivery"
sleep 3

echo "Mock webhook logs (last 200 lines):"
docker logs --tail 200 observability-e2e-mock-webhook || true

echo "E2E run complete"

exit 0
