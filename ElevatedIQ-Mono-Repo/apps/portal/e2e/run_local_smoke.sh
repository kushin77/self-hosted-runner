#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
MOCK_DIR="$ROOT_DIR/mock-server"

echo "Running portal local smoke test"

echo "1) Checking REST /api/events"
curl --silent --fail http://localhost:3001/api/events | head -n 5 || (echo "/api/events failed" && exit 2)

echo "2) Checking REST /api/runners"
curl --silent --fail http://localhost:3001/api/runners | head -n 5 || (echo "/api/runners failed" && exit 3)

echo "3) Verifying WebSocket streaming (3 clients, 8s)"
node "$MOCK_DIR/tmp_ws_smoke.js" ws://localhost:3001/ws/events 3 8 || (echo "ws smoke failed" && exit 4)

echo "4) Verifying vault-shim PUT/GET"
curl --silent --fail -X PUT http://localhost:8200/v1/secret/local-smoke -H "X-Vault-Token: root" -H "Content-Type: application/json" -d '{"value":"smoke-value"}' || (echo "vault put failed" && exit 5)
sleep 0.2
curl --silent --fail http://localhost:8200/v1/secret/local-smoke -H "X-Vault-Token: root" | grep -q "smoke-value" || (echo "vault get failed" && exit 6)

echo "Local smoke succeeded"
