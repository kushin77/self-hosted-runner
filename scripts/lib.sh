#!/usr/bin/env bash
set -euo pipefail

# Lightweight helper functions for secret retrieval and env handling
# Use: source scripts/lib.sh
# Supports GSM→Vault sync workflow for immutable credential rotation.

get_secret() {
  local secret_name="$1"
  local project="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo)}"
  if [[ -z "$project" ]]; then
    project="${PROJECT:-}"
  fi
  gcloud secrets versions access latest --secret="$secret_name" --project="$project" 2>/dev/null || echo ""
}

# Sync a single secret from GSM to Vault (no-op if Vault unavailable)
sync_secret_to_vault() {
  local secret_name="$1"
  local vault_path="${2:-secret/data/$secret_name}"
  
  if [[ -z "${VAULT_ADDR:-}" ]]; then
    return 0  # Vault not configured; skip sync
  fi
  
  VAULT_SKIP_VERIFY=${VAULT_SKIP_VERIFY:-true} \
    SECRET_NAME="$secret_name" VAULT_PATH="$vault_path" \
    bash "${SCRIPT_DIR:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/../vault/sync_gsm_to_vault.sh" 2>/dev/null || return 0
}

# Build a .env file from a list of GSM secret names (key=secret_name mapping)
# Usage: build_env_from_gsm output_file key1:secret1 key2:secret2 ...
build_env_from_gsm() {
  local out="$1"; shift
  : > "$out"
  for mapping in "$@"; do
    local key=${mapping%%:*}
    local secret=${mapping#*:}
    local val
    val=$(get_secret "$secret") || val=""
    if [[ -n "$val" ]]; then
      # If secret looks like JSON with payload keys, leave as-is; otherwise write simple KEY=VALUE
      if echo "$val" | grep -q "="; then
        echo "$val" >> "$out"
      else
        # Escape any EOF markers
        val=$(printf "%s" "$val" | sed 's/\r//g')
        printf "%s=%s\n" "$key" "$val" >> "$out"
      fi
    fi
  done
}

export -f get_secret sync_secret_to_vault build_env_from_gsm
