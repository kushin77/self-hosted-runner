#!/usr/bin/env bash
set -euo pipefail

# Idempotent Phase 3 provisioning script
# Expects env:
# - GCP_CREDENTIALS (JSON string)
# - GITHUB_TOKEN (token with repo scope to set secrets and update issues)
# - KUBECONFIG_B64 (optional, base64-encoded kubeconfig for helm)
# - VAULT_DEPLOY (true/false)

REPO=${REPO:-$(git config --get remote.origin.url || true)}
if [[ -z "$REPO" || "$REPO" == *"git@"* || "$REPO" == *"https:"* ]]; then
  ORIG=$(git config --get remote.origin.url || true)
  if [[ $ORIG == git@* ]]; then
    REPO=$(echo "$ORIG" | sed -E 's/.*:(.*)\.git/\1/')
  else
    REPO=$(echo "$ORIG" | sed -E 's#https?://[^/]+/([^/]+/[^/]+)(\.git)?#\1#')
  fi
fi
owner=${REPO%%/*}
repo=${REPO##*/}

echo "Provisioning Phase 3 for $owner/$repo"

if [[ -n "${KUBECONFIG_B64:-}" ]]; then
  echo "Writing kubeconfig"
  mkdir -p ~/.kube
  echo "$KUBECONFIG_B64" | base64 -d > ~/.kube/config
  export KUBECONFIG=~/.kube/config
fi

if [[ -n "${GCP_CREDENTIALS:-}" ]]; then
  echo "Writing GCP credentials to infra/gcp_creds.json"
  mkdir -p infra
  echo "$GCP_CREDENTIALS" > infra/gcp_creds.json
  chmod 600 infra/gcp_creds.json
fi

# Run Terraform for GCP WIF if infra/gcp-workload-identity.tf exists
if [ -f infra/gcp-workload-identity.tf ]; then
  echo "Running Terraform for GCP Workload Identity Federation"
  pushd infra >/dev/null
  terraform init -input=false || true
  terraform apply -auto-approve -input=false || true
  # Capture outputs if present
  if terraform output -json >/dev/null 2>&1; then
    outputs=$(terraform output -json)
    provider=$(echo "$outputs" | jq -r '.workload_identity_provider.value // empty') || true
    sa_email=$(echo "$outputs" | jq -r '.service_account_email.value // empty') || true
  fi
  popd >/dev/null
else
  echo "No infra/gcp-workload-identity.tf found; skipping terraform step."
fi

# If we have outputs and a GH token, update repo secrets via gh CLI if available
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    echo "Authenticating gh CLI"
    echo "$GITHUB_TOKEN" | gh auth login --with-token >/dev/null 2>&1 || true
    if [[ -n "${provider:-}" ]]; then
      echo "Setting repo secret GCP_WORKLOAD_IDENTITY_PROVIDER"
      gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$provider" --repo "$owner/$repo" || true
    fi
    if [[ -n "${sa_email:-}" ]]; then
      echo "Setting repo secret GCP_SERVICE_ACCOUNT_EMAIL"
      gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "$sa_email" --repo "$owner/$repo" || true
    fi
  else
    echo "gh CLI not available; cannot auto-set repo secrets. Print outputs instead:"
    echo "workload_identity_provider: ${provider:-}" 
    echo "service_account_email: ${sa_email:-}"
  fi
else
  echo "No GITHUB_TOKEN set; skipping repo secret updates"
fi

# Optional Vault deploy via Helm
if [[ "${VAULT_DEPLOY:-false}" == "true" ]]; then
  echo "Vault deployment requested"
  if [[ -z "${KUBECONFIG:-}" ]]; then
    echo "No KUBECONFIG available; cannot deploy Vault via Helm"
  else
    echo "Deploying Vault via Helm"
    helm repo add hashicorp https://helm.releases.hashicorp.com || true
    helm repo update || true
    # Idempotent install/upgrade
    if helm status vault -n vault >/dev/null 2>&1; then
      helm upgrade vault hashicorp/vault -n vault --create-namespace || true
    else
      helm install vault hashicorp/vault -n vault --create-namespace || true
    fi
    echo "Vault helm deploy attempted"
  fi
fi

# Run Phase3 summary generator and close incidents (idempotent)
if [[ -x ./scripts/phase3_generate_issue.sh ]]; then
  echo "Updating Phase 3 issue and closing incidents (if configured)"
  CLOSE_INCIDENTS=true GITHUB_TOKEN="$GITHUB_TOKEN" REPO="$owner/$repo" ./scripts/phase3_generate_issue.sh
else
  echo "Phase3 summary generator not found or not executable"
fi

echo "Phase 3 provisioning script completed"
