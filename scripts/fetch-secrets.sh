#!/usr/bin/env bash
# Fetch secrets from available secret manager (GCP Secret Manager, HashiCorp Vault)
# Fallback to environment variables. Designed to be idempotent and safe.

set -euo pipefail

echo "[fetch-secrets] Starting secret fetch"

# Helper: fetch from GCP Secret Manager
fetch_gsm() {
  local name="$1"
  if command -v gcloud >/dev/null 2>&1; then
    if gcloud secrets versions access latest --secret="$name" >/dev/null 2>&1; then
      echo "[fetch-secrets] Fetching $name from GCP Secret Manager"
      gcloud secrets versions access latest --secret="$name" || return 1
    else
      return 1
    fi
  else
    return 1
  fi
}

# Helper: fetch from Vault (KV v2 assumed)
fetch_vault() {
  local path="$1"
  if command -v vault >/dev/null 2>&1; then
    if vault kv get -field=value "$path" >/dev/null 2>&1; then
      echo "[fetch-secrets] Fetching $path from Vault"
      vault kv get -field=value "$path" || return 1
    else
      return 1
    fi
  else
    return 1
  fi
}

# For each required secret, try GSM -> Vault -> env var
require_secret() {
  local var_name="$1"   # e.g., DB_PASSWORD
  local gsm_name="$2"   # e.g., portal-db-password
  local vault_path="$3" # e.g., secret/data/portal/db_password (value field expected)

  if [ -n "${!var_name:-}" ]; then
    echo "[fetch-secrets] $var_name already set in environment"
    return 0
  fi

  # Try GSM
  if out=$(fetch_gsm "$gsm_name" 2>/dev/null || true); then
    export "$var_name"="$out"
    echo "[fetch-secrets] $var_name populated from GSM ($gsm_name)"
    return 0
  fi

  # Try Vault
  if out=$(fetch_vault "$vault_path" 2>/dev/null || true); then
    export "$var_name"="$out"
    echo "[fetch-secrets] $var_name populated from Vault ($vault_path)"
    return 0
  fi

  echo "[fetch-secrets] WARNING: $var_name not found in GSM/Vault and not set in environment"
  return 1
}

# List secrets required by Phase 6 (add or adjust as needed)
require_secret DB_PASSWORD portal-db-password secret/data/portal/db_password || true
require_secret REDIS_PASSWORD portal-redis-password secret/data/portal/redis_password || true
require_secret MQ_PASSWORD portal-mq-password secret/data/portal/mq_password || true
require_secret GRAFANA_PASSWORD portal-grafana-password secret/data/portal/grafana_password || true
require_secret API_TOKEN portal-api-token secret/data/portal/api_token || true

echo "[fetch-secrets] Completed (some secrets may be missing; verify before running builds)"

exit 0
