#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer for Secrets Store CSI driver and provider plugins (Vault + GCP GSM).
# Usage: ./scripts/automation/install_csi_and_providers.sh [--namespace kube-system]

NAMESPACE=${1:-kube-system}
HELM=${HELM:-helm}
KUBECTL=${KUBECTL:-kubectl}

echo "Installing Secrets Store CSI driver into namespace: $NAMESPACE"

# Add helm repo and update
if ! $HELM repo list | grep -q secrets-store; then
  $HELM repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
fi
$HELM repo update

# Install/upgrade driver
$HELM upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace $NAMESPACE --create-namespace \
  --set node.publishSecret.enabled=true --wait

# Install provider: Google Secret Manager provider
echo "Installing GCP provider (secrets-store-csi-driver-provider-gcp)"
GCP_PROVIDER_URL="https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp/releases/latest/download/gcp-provider.yaml"
$KUBECTL apply -f "$GCP_PROVIDER_URL"

# Install provider: Vault provider
echo "Installing Vault provider (secrets-store-csi-driver-provider-vault)"
VAULT_PROVIDER_URL="https://github.com/hashicorp/secrets-store-csi-driver-provider-vault/releases/latest/download/provider-installer.yaml"
$KUBECTL apply -f "$VAULT_PROVIDER_URL"

cat <<'EOF'
Installation requested for Secrets Store CSI Driver and providers (GCP/GSM and Vault).
Next steps:
- Ensure IRSA roles & IAM permissions for provider service accounts so they can access secrets (GSM/Vault) from cloud.
- Create SecretProviderClass manifests (examples in k8s/secretproviderclasses).
- Patch CronJob ServiceAccount to use CSI volume mounts per SecretProviderClass.
EOF
