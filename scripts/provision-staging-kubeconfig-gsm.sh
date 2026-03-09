#!/usr/bin/env bash
set -euo pipefail
# Idempotent provisioning of STAGING_KUBECONFIG into Google Secret Manager
# Usage: provision-staging-kubeconfig-gsm.sh --kubeconfig /path/to/kubeconfig --project PROJECT --secret-name SECRET_NAME

print_usage() {
  cat <<EOF
Usage: $0 --kubeconfig <file> --project <gcp-project> [--secret-name <name>] [--vault-path <path>]

Creates/updates a Google Secret Manager secret with the provided kubeconfig content.
If Vault is configured (VAULT_ADDR & VAULT_TOKEN) and 
`vault` CLI is present, it will optionally sync the secret to Vault at the provided --vault-path.

Environment:
  GCP credentials must be available via gcloud auth or ADC.
  Optionally set VAULT_ADDR and VAULT_TOKEN to sync to Vault.

Example:
  $0 --kubeconfig ./kubeconfig --project my-gcp-project --secret-name runner/STAGING_KUBECONFIG --vault-path secret/runner/staging_kubeconfig
EOF
}

KUBECONFIG_FILE=""
PROJECT=""
SECRET_NAME="runner/STAGING_KUBECONFIG"
VAULT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig) KUBECONFIG_FILE="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --secret-name) SECRET_NAME="$2"; shift 2;;
    --vault-path) VAULT_PATH="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 2;;
  esac
done

if [[ -z "$KUBECONFIG_FILE" || -z "$PROJECT" ]]; then
  echo "--kubeconfig and --project are required" >&2
  print_usage
  exit 2
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not found; please install and authenticate." >&2
  exit 2
fi

if [[ ! -f "$KUBECONFIG_FILE" ]]; then
  echo "Kubeconfig file not found: $KUBECONFIG_FILE" >&2
  exit 2
fi

KUBE_CONTENT=$(cat "$KUBECONFIG_FILE")

# Normalize secret name (no leading/trailing whitespace)
SECRET_NAME=$(echo -n "$SECRET_NAME" | tr -d '\r' | sed 's/^\s*//;s/\s*$//')

echo "Project: $PROJECT, Secret: $SECRET_NAME"

# Try to fetch existing secret payload (latest) and compare
EXISTING=""
if gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
  EXISTING=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="$PROJECT" 2>/dev/null || true)
fi

if [[ "$EXISTING" == "$KUBE_CONTENT" ]]; then
  echo "Secret $SECRET_NAME is up-to-date; no changes needed."
else
  if ! gcloud secrets describe "$SECRET_NAME" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Creating secret $SECRET_NAME (replication: automatic)"
    gcloud secrets create "$SECRET_NAME" --project="$PROJECT" --replication-policy="automatic"
  else
    echo "Secret $SECRET_NAME exists; will add a new version with updated value."
  fi

  echo -n "$KUBE_CONTENT" | gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT"
  echo "Added new secret version for $SECRET_NAME"
fi

# Optional: sync to Vault if configured
if [[ -n "$VAULT_PATH" && -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" ]] && command -v vault >/dev/null 2>&1; then
  echo "Syncing secret to Vault at $VAULT_PATH"
  # Use kv v2 if available; try kv get first
  if vault kv get -field=value "$VAULT_PATH" >/dev/null 2>&1; then
    CURRENT_VAULT=$(vault kv get -field=value "$VAULT_PATH" 2>/dev/null || true)
  else
    CURRENT_VAULT=""
  fi

  if [[ "$CURRENT_VAULT" == "$KUBE_CONTENT" ]]; then
    echo "Vault entry at $VAULT_PATH is up-to-date; skipping."
  else
    vault kv put "$VAULT_PATH" value="$(printf '%s' "$KUBE_CONTENT")"
    echo "Vault sync complete."
  fi
fi

echo "Provisioning complete."
