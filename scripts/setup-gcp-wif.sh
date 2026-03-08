#!/bin/bash

###############################################################################
# GCP Workload Identity Federation Setup for GitHub Actions
# 
# This script sets up Workload Identity Federation to allow GitHub Actions
# to authenticate to Google Cloud Platform without long-lived keys.
#
# Requirements:
#   - gcloud CLI installed and configured
#   - Proper GCP project access
#   - GCP_PROJECT_ID environment variable set
#   - GCP_PROJECT_NUMBER available
#
# Output:
#   - WIP_PROVIDER URI (save to GitHub secret)
#   - Service account email
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

###############################################################################
# CONFIGURATION
###############################################################################

# Default values (can be overridden by environment)
GCP_PROJECT_ID="${GCP_PROJECT_ID:=}"
GCP_REGION="${GCP_REGION:=global}"
WORKLOAD_POOL_ID="${WORKLOAD_POOL_ID:=github-pool}"
WORKLOAD_PROVIDER_ID="${WORKLOAD_PROVIDER_ID:=github-provider}"
SERVICE_ACCOUNT_ID="${SERVICE_ACCOUNT_ID:=github-actions-gsm}"
GITHUB_REPO="${GITHUB_REPO:=kushin77/self-hosted-runner}"

# Output file for credentials
OUTPUT_FILE="${OUTPUT_FILE:=/tmp/gcp-wif-credentials.txt}"

###############################################################################
# VALIDATION
###############################################################################

log_info "Starting GCP Workload Identity Federation setup..."
echo ""

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

log_success "gcloud CLI found"

# Get or request GCP Project ID
if [[ -z "$GCP_PROJECT_ID" ]]; then
    read -p "Enter your GCP Project ID: " GCP_PROJECT_ID
fi

log_info "Using GCP Project: $GCP_PROJECT_ID"

# Validate project exists
if ! gcloud projects describe "$GCP_PROJECT_ID" --quiet 2>/dev/null; then
    log_error "Project $GCP_PROJECT_ID not found or not accessible"
    exit 1
fi

log_success "Project validated"

# Get project number
GCP_PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectNumber)')
log_success "Project number: $GCP_PROJECT_NUMBER"

###############################################################################
# STEP 1: Enable Required APIs
###############################################################################

log_info ""
log_info "Step 1: Enabling required APIs..."

APIs=(
    "iam.googleapis.com"
    "iap.googleapis.com"
    "sts.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "secretmanager.googleapis.com"
)

for api in "${APIs[@]}"; do
    log_info "Enabling $api..."
    gcloud services enable "$api" --project="$GCP_PROJECT_ID" --quiet || \
        log_warning "Failed to enable $api (may already be enabled)"
done

log_success "APIs enabled (or already enabled)"

###############################################################################
# STEP 2: Create Service Account
###############################################################################

log_info ""
log_info "Step 2: Creating service account..."

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_ID}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" \
    --project="$GCP_PROJECT_ID" &>/dev/null; then
    log_warning "Service account $SERVICE_ACCOUNT_EMAIL already exists, skipping creation"
else
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_ID" \
        --display-name="GitHub Actions GSM Access" \
        --project="$GCP_PROJECT_ID"
    
    log_success "Service account created: $SERVICE_ACCOUNT_EMAIL"
fi

###############################################################################
# STEP 3: Grant Necessary Permissions
###############################################################################

log_info ""
log_info "Step 3: Granting permissions..."

ROLES=(
    "roles/secretmanager.secretAccessor"
    "roles/secretmanager.admin"
)

for role in "${ROLES[@]}"; do
    log_info "Granting $role..."
    gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="$role" \
        --quiet 2>&1 | grep -v "^Updated IAM policy" || true
done

log_success "Permissions granted"

###############################################################################
# STEP 4: Create Workload Identity Pool
###############################################################################

log_info ""
log_info "Step 4: Creating Workload Identity Pool..."

POOL_NAME="projects/${GCP_PROJECT_NUMBER}/locations/${GCP_REGION}/workloadIdentityPools/${WORKLOAD_POOL_ID}"

# Check if pool exists
if gcloud iam workload-identity-pools describe "$WORKLOAD_POOL_ID" \
    --location="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" &>/dev/null; then
    log_warning "Workload identity pool $WORKLOAD_POOL_ID already exists, skipping creation"
else
    gcloud iam workload-identity-pools create "$WORKLOAD_POOL_ID" \
        --project="$GCP_PROJECT_ID" \
        --location="$GCP_REGION" \
        --display-name="GitHub Actions Pool" \
        --disabled=false
    
    log_success "Workload identity pool created: $WORKLOAD_POOL_ID"
fi

###############################################################################
# STEP 5: Create Workload Identity Pool Provider
###############################################################################

log_info ""
log_info "Step 5: Creating Workload Identity Pool Provider..."

# Extract GitHub repository owner
GITHUB_OWNER=$(echo "$GITHUB_REPO" | cut -d'/' -f1)

# Check if provider exists
if gcloud iam workload-identity-pools providers describe "$WORKLOAD_PROVIDER_ID" \
    --workload-identity-pool="$WORKLOAD_POOL_ID" \
    --location="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" &>/dev/null; then
    log_warning "Workload identity pool provider $WORKLOAD_PROVIDER_ID already exists, skipping creation"
else
    gcloud iam workload-identity-pools providers create-oidc "$WORKLOAD_PROVIDER_ID" \
        --project="$GCP_PROJECT_ID" \
        --location="$GCP_REGION" \
        --workload-identity-pool="$WORKLOAD_POOL_ID" \
        --display-name="GitHub Actions OIDC Provider" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --issuer-uri=https://token.actions.githubusercontent.com \
        --attribute-condition="assertion.repository_owner == '${GITHUB_OWNER}'"
    
    log_success "Workload identity pool provider created: $WORKLOAD_PROVIDER_ID"
fi

###############################################################################
# STEP 6: Get Workload Identity Provider Resource Name
###############################################################################

log_info ""
log_info "Step 6: Retrieving Workload Identity Provider URI..."

WIP_PROVIDER=$(gcloud iam workload-identity-pools providers describe "$WORKLOAD_PROVIDER_ID" \
    --workload-identity-pool="$WORKLOAD_POOL_ID" \
    --location="$GCP_REGION" \
    --project="$GCP_PROJECT_ID" \
    --format='value(name)')

if [[ -z "$WIP_PROVIDER" ]]; then
    log_error "Failed to retrieve WIP provider URI"
    exit 1
fi

log_success "WIP Provider URI: $WIP_PROVIDER"

###############################################################################
# STEP 7: Grant Workload Identity Federation Access
###############################################################################

log_info ""
log_info "Step 7: Granting Workload Identity Federation access..."

# Create the principal set for the GitHub repository
PRINCIPAL_SET="principalSet://iam.googleapis.com/projects/${GCP_PROJECT_NUMBER}/locations/${GCP_REGION}/workloadIdentityPools/${WORKLOAD_POOL_ID}/attribute.repository/${GITHUB_REPO}"

gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT_EMAIL" \
    --project="$GCP_PROJECT_ID" \
    --role=roles/iam.workloadIdentityUser \
    --member="$PRINCIPAL_SET" \
    --quiet 2>&1 | grep -v "^Updated IAM policy" || true

log_success "Workload Identity User role granted"

###############################################################################
# STEP 8: Save Credentials to File
###############################################################################

log_info ""
log_info "Step 8: Saving credentials..."

cat > "$OUTPUT_FILE" <<EOF
###############################################################################
# GCP Workload Identity Federation - GitHub Actions Setup
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
###############################################################################

# 1. GCP Project Information
GCP_PROJECT_ID=${GCP_PROJECT_ID}
GCP_PROJECT_NUMBER=${GCP_PROJECT_NUMBER}

# 2. Service Account
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_EMAIL}

# 3. Workload Identity Federation Provider
# ⭐ SAVE THIS TO GITHUB SECRET: GCP_WORKLOAD_IDENTITY_PROVIDER
GCP_WORKLOAD_IDENTITY_PROVIDER=${WIP_PROVIDER}

# 4. GitHub Configuration
GITHUB_REPO=${GITHUB_REPO}
GITHUB_OWNER=${GITHUB_OWNER}

###############################################################################
# How to use in GitHub Actions workflows:
###############################################################################

# In your workflow, add this step to authenticate:

jobs:
  example:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: google-github-actions/auth@v1
        with:
          workload_identity_provider: \${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account_email: \${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      
      - uses: google-github-actions/setup-gcloud@v1
      
      - name: Retrieve secret from GSM
        run: |
          gcloud secrets versions access latest --secret="docker-hub-password"

###############################################################################
# Create these GitHub Secrets:
###############################################################################

1. GCP_PROJECT_ID = ${GCP_PROJECT_ID}
2. GCP_SERVICE_ACCOUNT_EMAIL = ${SERVICE_ACCOUNT_EMAIL}
3. GCP_WORKLOAD_IDENTITY_PROVIDER = ${WIP_PROVIDER}

###############################################################################
# Verify Setup:
###############################################################################

# Check service account has correct roles:
gcloud iam service-accounts get-iam-policy ${SERVICE_ACCOUNT_EMAIL} --project=${GCP_PROJECT_ID}

# Test authentication (requires GitHub token):
# gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "${WIP_PROVIDER}"

EOF

log_success "Credentials saved to $OUTPUT_FILE"

###############################################################################
# SUMMARY
###############################################################################

log_info ""
log_info "═══════════════════════════════════════════════════════════════════════"
log_success "GCP Workload Identity Federation Setup Complete!"
log_info "═══════════════════════════════════════════════════════════════════════"
echo ""

echo "✅ Workload Identity Pool: $WORKLOAD_POOL_ID"
echo "✅ OIDC Provider: $WORKLOAD_PROVIDER_ID"
echo "✅ Service Account: $SERVICE_ACCOUNT_EMAIL"
echo ""

echo "📋 Create these GitHub Secrets:"
echo "   1. GCP_PROJECT_ID = $GCP_PROJECT_ID"
echo "   2. GCP_SERVICE_ACCOUNT_EMAIL = $SERVICE_ACCOUNT_EMAIL"
echo "   3. GCP_WORKLOAD_IDENTITY_PROVIDER = $WIP_PROVIDER"
echo ""

echo "📝 Full configuration saved to: $OUTPUT_FILE"
echo ""

echo "🚀 Next steps:"
echo "   1. Copy the GCP_WORKLOAD_IDENTITY_PROVIDER value above"
echo "   2. Add to GitHub repository secrets:"
echo "      gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body '$WIP_PROVIDER'"
echo "   3. Add GCP_PROJECT_ID and GCP_SERVICE_ACCOUNT_EMAIL to secrets"
echo "   4. Test with: .github/workflows/test-credential-helpers.yml"
echo ""

log_success "Setup complete!"
