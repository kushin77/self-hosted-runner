#!/usr/bin/env bash
set -euo pipefail

GSM_PROJECT="nexusshield-prod"
KEYVAULT_NAME="nsv298610"
LOG="/tmp/mirror_gsm_to_azure_$(date -u +%Y%m%dT%H%M%SZ).log"

echo "Mirror run started at $(date -u)" | tee -a "$LOG"

if ! command -v gcloud >/dev/null; then echo "gcloud not found"; exit 1; fi
if ! command -v az >/dev/null; then echo "az not found"; exit 1; fi

while IFS= read -r secret_name; do
  [ -z "$secret_name" ] && continue
  echo "\nProcessing: $secret_name" | tee -a "$LOG"
  secret_value=$(gcloud secrets versions access latest --secret="$secret_name" --project="$GSM_PROJECT" 2>/dev/null || true)
  if [ -z "$secret_value" ]; then
    echo "  SKIP: secret not found in GSM" | tee -a "$LOG"
    continue
  fi
  # derive KV-safe name
  kv_name=$(printf '%s' "$secret_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//; s/-$//')
  if [ -z "$kv_name" ]; then
    echo "  SKIP: invalid kv name" | tee -a "$LOG"
    continue
  fi
  # fetch existing
  existing=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$kv_name" --query value -o tsv 2>/dev/null || echo "")
  # compare
  if [ -n "$existing" ]; then
    new_hash=$(printf '%s' "$secret_value" | sha256sum | awk '{print $1}')
    existing_hash=$(printf '%s' "$existing" | sha256sum | awk '{print $1}')
    if [ "$new_hash" = "$existing_hash" ]; then
      echo "  SKIP: unchanged in Key Vault ($kv_name)" | tee -a "$LOG"
      continue
    fi
  fi
  # set secret
  if az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "$kv_name" --value "$secret_value" >/dev/null 2>&1; then
    echo "  SET: $secret_name -> $kv_name" | tee -a "$LOG"
  else
    echo "  FAILED: $secret_name -> $kv_name" | tee -a "$LOG"
  fi
done < /tmp/gsm_secrets_list.txt

echo "Mirror run completed at $(date -u)" | tee -a "$LOG"

echo "Log: $LOG"
