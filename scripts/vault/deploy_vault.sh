#!/usr/bin/env bash
set -euo pipefail

# Idempotent Vault deployment via Helm (assumes kubectl configured)
# - Uses Helm chart: hashicorp/vault
# - Configures auto-unseal with an existing KMS key
# Usage: ./scripts/vault/deploy_vault.sh <k8s-namespace> <gcp-project> <gcp-kms-key-ring> <gcp-kms-key-name>

NAMESPACE=${1:-vault}
PROJECT=${2:-}
KMS_KEY_RING=${3:-}
KMS_KEY_NAME=${4:-}

if [ -z "$PROJECT" ] || [ -z "$KMS_KEY_RING" ] || [ -z "$KMS_KEY_NAME" ]; then
  echo "Usage: $0 <k8s-namespace> <gcp-project> <gcp-kms-key-ring> <gcp-kms-key-name>"
  exit 2
fi

helm repo add hashicorp https://helm.releases.hashicorp.com || true
helm repo update

# Create namespace if missing
kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE"

# Build Helm values (minimal secure defaults). Adjust as needed in CI/operator.
TMP_VALUES=$(mktemp)
cat > "$TMP_VALUES" <<EOF
server:
  affinity: {}
  ha:
    enabled: true
    replicas: 3
  dataStorage:
    enabled: true
    storageClass: standard
  extraEnvironmentVars:
    VAULT_CLOUD_KMS_KEY_PROJECT: "$PROJECT"
    VAULT_CLOUD_KMS_KEY_RING: "$KMS_KEY_RING"
    VAULT_CLOUD_KMS_KEY_NAME: "$KMS_KEY_NAME"
  # Auto-unseal configuration uses the GCP KMS plugin within Vault
  # See official docs for secure RBAC and workload identity setup

ui:
  enabled: false

EOF

helm upgrade --install vault hashicorp/vault -n "$NAMESPACE" -f "$TMP_VALUES" --wait
rm -f "$TMP_VALUES"

echo "Vault helm release installed/updated in namespace $NAMESPACE"

echo "NOTE: Ensure the Vault chart has access to GCP KMS (workload identity/service account) for auto-unseal."
