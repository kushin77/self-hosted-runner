#!/usr/bin/env bash
set -euo pipefail

# Auto-deploy observability artifacts (Prometheus rules + Grafana dashboards + Log shipping)
# Idempotent, requires operator host with network access to Prometheus/Grafana/worker nodes.
# Credentials are retrieved from one of: GSM, Vault, or environment variables.

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MON_DIR="$ROOT_DIR/monitoring"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
err() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $0 [--prom-host PROM_HOST] [--prom-ssh-user USER] [--grafana-host HOST] [--grafana-token SECRET_NAME|ENV_VAR]

  Environment / secrets options:
  SECRETS_BACKEND: gsm|vault|env  (default: env)
  For gsm: set GSM_PROJECT and pass secret names (e.g. GRAFANA_TOKEN_SECRET)
  For vault: set VAULT_ADDR and ensure Vault auth is available via agent or environment (do NOT embed tokens in files)

Examples:
  SECRETS_BACKEND=env $0 --prom-host prometheus.internal --grafana-host grafana.internal --grafana-token "env:GRAFANA_API_TOKEN"
  SECRETS_BACKEND=gsm GSM_PROJECT=my-proj $0 --prom-host prometheus.internal --grafana-host grafana.internal --grafana-token secret:grafana/api-token

This script does NOT embed credentials; it fetches them at runtime as configured.
EOF
}

PROM_HOST=""
PROM_SSH_USER=""
GRAFANA_HOST=""
GRAFANA_TOKEN_REF=""
SECRETS_BACKEND="${SECRETS_BACKEND:-env}"
GSM_PROJECT="${GSM_PROJECT:-}"
VAULT_ADDR="${VAULT_ADDR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prom-host) PROM_HOST="$2"; shift 2;;
    --prom-ssh-user) PROM_SSH_USER="$2"; shift 2;;
    --grafana-host) GRAFANA_HOST="$2"; shift 2;;
    --grafana-token) GRAFANA_TOKEN_REF="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1";;
  esac
done

fetch_secret() {
  local ref="$1"
  # ref format: env:VARNAME | secret:secret-name | vault:path#field
  if [[ "$ref" == env:* ]]; then
    local var=${ref#env:}
    printf "%s" "${!var:-}"
    return
  fi
  if [[ "$SECRETS_BACKEND" == "gsm" && "$ref" == secret:* ]]; then
    if [ -z "$GSM_PROJECT" ]; then err "GSM_PROJECT required for gsm backend"; fi
    local secret_name=${ref#secret:}
    gcloud secrets versions access latest --secret="$secret_name" --project="$GSM_PROJECT"
    return
  fi
  if [[ "$SECRETS_BACKEND" == "vault" && "$ref" == vault:* ]]; then
    # format vault:path#field
    local path_field=${ref#vault:}
    local path=${path_field%%#*}
    local field=${path_field#*#}
    if [ -z "$VAULT_ADDR" ]; then err "VAULT_ADDR required for vault backend"; fi
    vault kv get -field="$field" "$path"
    return
  fi
  err "Unsupported secret ref or backend: $ref (backend=$SECRETS_BACKEND)"
}

ensure_prometheus_rules() {
  [ -z "$PROM_HOST" ] && log "Skipping Prometheus rules (no --prom-host)" && return
  local rules_file="$MON_DIR/prometheus-alerting-rules.yml"
  if [ -z "$PROM_SSH_USER" ]; then
    log "Attempting HTTP reload on Prometheus host $PROM_HOST"
    # We assume rules are managed via config management or this script runs on host
    err "No ssh user provided; please run this script on Prometheus host or provide --prom-ssh-user"
  fi
  log "Copying rules to $PROM_SSH_USER@$PROM_HOST:/etc/prometheus/rules/"
  scp "$rules_file" "$PROM_SSH_USER@$PROM_HOST:/tmp/monitoring-prometheus-alerting-rules.yml"
  ssh "$PROM_SSH_USER@$PROM_HOST" sudo mv /tmp/monitoring-prometheus-alerting-rules.yml /etc/prometheus/rules/prometheus-alerting-rules.yml && sudo chown prometheus:prometheus /etc/prometheus/rules/prometheus-alerting-rules.yml || err "Failed to move rules on Prometheus host"
  ssh "$PROM_SSH_USER@$PROM_HOST" 'sudo systemctl reload prometheus || (curl -sS -X POST http://localhost:9090/-/reload || true)'
  log "Prometheus rules deployed and reload triggered on $PROM_HOST"
}

import_grafana_dashboards() {
  [ -z "$GRAFANA_HOST" ] && log "Skipping Grafana import (no --grafana-host)" && return
  if [ -z "$GRAFANA_TOKEN_REF" ]; then err "Grafana token not provided; use --grafana-token ref"; fi
  local token
  token=$(fetch_secret "$GRAFANA_TOKEN_REF") || err "Failed to fetch Grafana token"
  for f in "$MON_DIR"/grafana-dashboard-*.json; do
    [ -f "$f" ] || continue
    log "Importing dashboard $f to $GRAFANA_HOST"
    curl -sS -X POST "${GRAFANA_HOST%/}/api/dashboards/db" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' \
      -d @"$f" || log "Warning: grafana import may have failed for $f"
  done
  log "Grafana import finished"
}

apply_log_shipping() {
  # call existing script which is idempotent
  local script="$ROOT_DIR/scripts/apply-elk-credentials-to-filebeat.sh"
  if [ -x "$script" ]; then
    log "Applying Filebeat/ELK credentials via $script"
    "$script" --dry-run || log "Dry-run completed (use without --dry-run to apply)"
  else
    log "No Filebeat ELK script found; skipping log shipping step"
  fi
}

main() {
  log "Starting observability deployment (idempotent)"
  ensure_prometheus_rules
  import_grafana_dashboards
  apply_log_shipping
  log "Observability deployment script completed (operations actions required for live apply)"
}

main
