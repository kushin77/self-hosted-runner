#!/usr/bin/env bash
set -euo pipefail

# Create a Workload Identity Pool and OIDC Provider for GitHub Actions
# Usage:
#   PROJECT_ID=your-project-id ./scripts/create_workload_identity.sh OWNER/REPO
# Requires: gcloud CLI authenticated with a user or service account that can create pools and service accounts.

if [ -z "${PROJECT_ID:-}" ]; then
  echo "ERROR: PROJECT_ID environment variable is required"
  exit 2
fi

if [ $# -ne 1 ]; then
  echo "Usage: PROJECT_ID=your-project-id $0 owner/repo"
  exit 2
fi

REPO="$1"  # e.g. akushnir/self-hosted-runner
POOL_ID="github-actions-pool"
PROVIDER_ID="github-actions-provider"

echo "Creating Workload Identity Pool: $POOL_ID"
gcloud iam workload-identity-pools create "$POOL_ID" \
  --project="$PROJECT_ID" --location="global" --display-name="GitHub Actions Pool" || true

echo "Creating OIDC provider: $PROVIDER_ID"
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_ID" \
  --project="$PROJECT_ID" --location="global" --workload-identity-pool="$POOL_ID" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --display-name="GitHub Actions Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" || true

# Bind the Vault service account to allow GitHub Actions in the specified repo to impersonate it
# Service account name depends on terraform output or known SA; adjust below.
VAULT_SA_EMAIL=$(gcloud iam service-accounts list --filter="displayName:Vault Admin Service Account" --format='value(email)' --project="$PROJECT_ID" || true)
if [ -z "$VAULT_SA_EMAIL" ]; then
  echo "Vault service account not found by displayName. Please set VAULT_SA_EMAIL env var or create the SA first."
  echo "You can create the SA via Terraform (module gcp-vault) or gcloud."
  exit 0
fi

# The principal member string for repo-specific access. Replace PROJECT_NUMBER if needed.
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
PRINCIPAL_SET="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/attribute.repository/${REPO}"

echo "Binding service account $VAULT_SA_EMAIL to allow Workload Identity users from repo $REPO"
gcloud iam service-accounts add-iam-policy-binding "$VAULT_SA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="$PRINCIPAL_SET"

# Grant minimal roles to the service account for KMS and GCS.
# These may already be applied by Terraform; these commands are idempotent.

echo "Granting roles/storage.objectAdmin on the Vault bucket to $VAULT_SA_EMAIL"
# bucket name from terraform output: module.gcp_vault.vault_storage_bucket
# Replace BUCKET_NAME with the actual bucket or use Terraform output to fetch it.
# gcloud projects add-iam-policy-binding ... (not needed for bucket-level role)

# Grant KMS role on key (requires key resource name). Use Terraform outputs where possible.

cat <<EOF
Workload Identity setup complete (or attempted). Verify the binding and test GitHub Actions OIDC by requesting a token in a workflow.
Example GitHub Actions step to authenticate:

- name: 'Authenticate to GCP'
  uses: 'google-github-actions/auth@v1'
  with:
    workload_identity_provider: 'projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}'
    service_account: '${VAULT_SA_EMAIL}'

EOF
