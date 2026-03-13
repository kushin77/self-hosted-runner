#!/usr/bin/env bash
set -euo pipefail

## Example: run Vault Agent to render environment variables for docker-compose
## This is a template/example only — adapt paths, secret names, and agent config to your environment.

# Usage: ./vault-agent-example.sh start|stop|run-once

MODE=${1:-run-once}
WORKDIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$WORKDIR/vault-env.tpl"
OUT_ENV="$WORKDIR/.env.tmp"
AGENT_CONFIG="$WORKDIR/vault-agent-config.hcl"

case "$MODE" in
  start)
    echo "Starting Vault Agent in background (system service recommended)."
    vault agent -config="$AGENT_CONFIG" &
    ;;
  stop)
    echo "Stopping Vault Agent (killall vault-agent)."
    pkill -f 'vault agent' || true
    ;;
  run-once)
    echo "Rendering template to ephemeral env file: $OUT_ENV"
    vault read -format=json secret/data/portal | jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' > "$OUT_ENV"
    chmod 600 "$OUT_ENV"
    echo "Starting docker compose with --env-file $OUT_ENV"
    docker compose --env-file "$OUT_ENV" up -d --build
    # Wait a bit then remove the temp file
    sleep 5
    shred -u "$OUT_ENV" || rm -f "$OUT_ENV"
    ;;
  *)
    echo "Usage: $0 start|stop|run-once"
    exit 1
    ;;
esac
