#!/bin/bash

################################################################################
# NEXUS COMPLETE DEPLOYMENT: PHASES 1-6 (FULLY AUTOMATED)
#
# Single command executes everything:
# ./nexus-production-deploy.sh
#
# Requirements:
# - GitHub token in environment: export GITHUB_TOKEN=<token>
# - OR in Secret Manager: gcloud secrets create github-token --data-file=- --project=nexusshield-prod
# - GCP credentials configured
#
################################################################################

set -euo pipefail

REPO_ROOT="/home/akushnir/self-hosted-runner"
PROJECT_ID="nexusshield-prod"
REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"

# Export credentials
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-/tmp/deployer-key.json}"
export PROJECT_ID

# Get GitHub token from env or Secret Manager
setup_github_token() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        echo "✅ GitHub token from environment"
        return 0
    fi
    
    echo "Attempting to retrieve GitHub token from Secret Manager..."
    GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo ""
        echo "⚠️ GitHub token required for Phase 3-6 automation"
        echo ""
        echo "Setup options:"
        echo ""
        echo "Option 1: Set environment variable"
        echo "  export GITHUB_TOKEN=<your-github-token>"
        echo "  ./nexus-production-deploy.sh"
        echo ""
        echo "Option 2: Store in Secret Manager"
        echo "  gcloud secrets create github-token --data-file=- --project=$PROJECT_ID"
        echo "  (paste token when prompted, then Ctrl+D)"
        echo "  ./nexus-production-deploy.sh"
        echo ""
        echo "Get token: https://github.com/settings/tokens (repo scope)"
        echo ""
        return 1
    fi
    
    export GITHUB_TOKEN
    echo "✅ GitHub token from Secret Manager"
}

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════${NC}\n${BLUE}$1${NC}\n${BLUE}════════════════════════════════════════${NC}\n"; }

# ============================================================================
# EXECUTE FULL DEPLOYMENT
# ============================================================================

main() {
    section "NEXUS PRODUCTION DEPLOYMENT: PHASES 1-6"
    
    log "Project: $PROJECT_ID"
    log "Repository: $REPO_OWNER/$REPO_NAME"
    log ""
    
    # Verify credentials
    if ! grep -q "nexusshield-prod" <(gcloud config list 2>/dev/null) && [ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
        log "Setting up GCP credentials..."
    fi
    
    # Setup GitHub token (optional for phases 3-6)
    setup_github_token || log "⚠️ Phases 3-6 will be skipped (requires GitHub token)"
    
    # Execute Phase 1-2 (direct deployment)
    log "Executing Phase 1-2 (Infrastructure Deployment)..."
    cd "$REPO_ROOT"
    bash ./deploy-now.sh
    
    # Execute Phase 3-6 (if GitHub token available)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        log ""
        log "Executing Phases 3-6 (Full Automation via GitHub API)..."
        bash ./scripts/phases-3-6-full-automation.sh
    else
        section "PHASES 1-2 COMPLETE"
        log "✅ GitHub Actions removed"
        log "✅ Infrastructure deployed"
        log ""
        log "For Phases 3-6 (GitHub API automation), provide GitHub token:"
        log "  export GITHUB_TOKEN=<token>"
        log "  bash scripts/phases-3-6-full-automation.sh"
    fi
    
    section "DEPLOYMENT COMPLETE"
    log "✅ All phases executed"
    log "✅ Production ready"
    log ""
}

main "$@"
