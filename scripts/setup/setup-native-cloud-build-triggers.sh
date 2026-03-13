#!/bin/bash
#
# Cloud Build Native Triggers Setup - Organization Admin Script
# Purpose: Create native GitHub-backed Cloud Build triggers after OAuth
# Status: Ready to run (paste output URL in browser for OAuth)
# Date: March 13, 2026
#

set -euo pipefail

PROJECT_ID="${GCP_PROJECT:-nexusshield-prod}"
GITHUB_ORG="kushin77"
GITHUB_REPO="self-hosted-runner"
REGION="global"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

# ============================================================================
# STEP 1: Authorize GitHub Connection (Interactive)
# ============================================================================
create_github_connection() {
    log_info "Step 1: Creating GitHub Connection (requires browser authorization)"
    log_warning "You will be prompted to authorize the Cloud Build GitHub App"
    
    if gcloud builds connections create github \
        --region="$REGION" \
        --name=github-connection \
        --project="$PROJECT_ID"; then
        log_success "GitHub connection created and authorized"
    else
        log_error "Failed to create GitHub connection. Please authorize manually in Google Cloud Console."
    fi
}

# ============================================================================
# STEP 2: Create Policy Check Trigger
# ============================================================================
create_policy_check_trigger() {
    log_info "Step 2: Creating policy-check-trigger"
    
    if gcloud builds triggers create github \
        --name="policy-check-trigger" \
        --region="$REGION" \
        --repo-owner="$GITHUB_ORG" \
        --repo-name="$GITHUB_REPO" \
        --branch-pattern="^main$" \
        --build-config="cloudbuild.policy-check.yaml" \
        --project="$PROJECT_ID" \
        --service-account="projects/$PROJECT_ID/serviceAccounts/prod-deployer@${PROJECT_ID}.iam.gserviceaccount.com"; then
        log_success "policy-check-trigger created"
    else
        log_error "Failed to create policy-check-trigger"
    fi
}

# ============================================================================
# STEP 3: Create Direct Deploy Trigger
# ============================================================================
create_direct_deploy_trigger() {
    log_info "Step 3: Creating direct-deploy-trigger"
    
    if gcloud builds triggers create github \
        --name="direct-deploy-trigger" \
        --region="$REGION" \
        --repo-owner="$GITHUB_ORG" \
        --repo-name="$GITHUB_REPO" \
        --branch-pattern="^main$" \
        --build-config="cloudbuild.yaml" \
        --project="$PROJECT_ID" \
        --service-account="projects/$PROJECT_ID/serviceAccounts/prod-deployer@${PROJECT_ID}.iam.gserviceaccount.com"; then
        log_success "direct-deploy-trigger created"
    else
        log_error "Failed to create direct-deploy-trigger"
    fi
}

# ============================================================================
# STEP 4: Apply Branch Protection (requires GitHub CLI)
# ============================================================================
apply_branch_protection() {
    log_info "Step 4: Applying branch protection rules"
    
    # Create JSON payload for branch protection
    cat > /tmp/branch_protection_final.json << 'EOFBP'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "policy-check-trigger",
      "direct-deploy-trigger"
    ]
  },
  "required_pull_request_reviews": {
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "enforce_admins": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true,
  "restrictions": null
}
EOFBP

    if command -v gh &> /dev/null; then
        TOKEN=$(gh auth token 2>/dev/null || echo "")
        if [ -z "$TOKEN" ]; then
            log_warning "GitHub CLI not authenticated. Skipping branch protection setup."
            return
        fi
        
        if curl -s -X PUT "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/branches/main/protection" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d @/tmp/branch_protection_final.json | grep -q "message"; then
            log_warning "Branch protection API response - check manually in GitHub Settings"
        else
            log_success "Branch protection applied"
        fi
    else
        log_warning "GitHub CLI not found. Apply branch protection manually:"
        echo "  GitHub → Settings → Branches → main → Add branch protection"
        echo "  - Require: policy-check-trigger, direct-deploy-trigger"
        echo "  - Require PR approvals: 1 (require CODEOWNERS)"
        echo "  - Enforce admins: Yes"
    fi
}

# ============================================================================
# STEP 5: Verify Triggers
# ============================================================================
verify_triggers() {
    log_info "Step 5: Verifying triggers"
    
    log_info "Cloud Build triggers in project $PROJECT_ID:"
    gcloud builds triggers list \
        --project="$PROJECT_ID" \
        --filter="name:(policy-check-trigger OR direct-deploy-trigger)" \
        --format="table(name, filename, branch_name)" || true
    
    log_info "Triggers should appear above. If empty, check gcloud builds triggers list output."
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "  Cloud Build Native Triggers Setup"
    echo "  Project: $PROJECT_ID"
    echo "  Repository: $GITHUB_ORG/$GITHUB_REPO"
    echo "════════════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "Prerequisites check..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Install from https://cloud.google.com/sdk/docs/install"
    fi
    
    if ! gcloud config get-value project &>/dev/null; then
        log_error "gcloud not configured. Run: gcloud init"
    fi
    
    log_success "Prerequisites OK"
    echo ""
    
    # Execute steps
    create_github_connection
    echo ""
    create_policy_check_trigger
    echo ""
    create_direct_deploy_trigger
    echo ""
    verify_triggers
    echo ""
    apply_branch_protection
    echo ""
    
    log_success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Test a commit: git commit --allow-empty -m 'test' && git push origin main"
    echo "  2. Watch builds: gcloud builds log $(gcloud builds list --limit=1 --format='value(id)')"
    echo "  3. Verify status: gh api repos/$GITHUB_ORG/$GITHUB_REPO/branches/main/protection"
    echo ""
}

main "$@"
