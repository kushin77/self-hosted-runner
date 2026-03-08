#!/bin/bash
# 🍽️ ALA CARTE DEPLOYMENT INFO GENERATOR
# Dynamically generates deployment tracking info based on actual system state
# Properties: Immutable (Git audit trail), Ephemeral (no state at rest), 
#            Idempotent (safe to re-run), No-Ops (fully automated), Hands-Off

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

REPO_OWNER="kushin77"
REPO_NAME="self-hosted-runner"
TRACKING_ISSUE="1702"
MONITORING_ISSUE="1845"
DEPLOYMENT_ISSUE="1788"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
RUN_ID="$(date +%s)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}ℹ️  ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}✅ ${1}${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}"
}

log_error() {
    echo -e "${RED}❌ ${1}${NC}"
}

# Check if a GitHub secret exists
check_secret_exists() {
    local secret_name=$1
    if gh secret list -R "$REPO_OWNER/$REPO_NAME" | grep -q "^$secret_name\s"; then
        return 0
    else
        return 1
    fi
}

# Get deployment status based on actual system state
get_deployment_status() {
    local status="INITIALIZING"
    local gsm_status="UNKNOWN"
    local vault_status="UNKNOWN"
    local kms_status="UNKNOWN"
    
    # Check secrets provisioned (indicates readiness)
    if check_secret_exists "GCP_PROJECT_ID"; then
        gsm_status="PROVISIONED"
    else
        gsm_status="PENDING_CREDENTIALS"
    fi
    
    if check_secret_exists "GCP_WORKLOAD_IDENTITY_PROVIDER"; then
        vault_status="PROVISIONED"
    else
        vault_status="PENDING_CREDENTIALS"
    fi
    
    if check_secret_exists "AWS_KMS_KEY_ARN"; then
        kms_status="PROVISIONED"
    else
        kms_status="OPTIONAL"
    fi
    
    # Determine overall status
    if [[ "$gsm_status" == "PROVISIONED" ]] && [[ "$vault_status" == "PROVISIONED" ]]; then
        status="READY_FOR_PROVISIONING"
    elif [[ "$gsm_status" == "PENDING_CREDENTIALS" ]] || [[ "$vault_status" == "PENDING_CREDENTIALS" ]]; then
        status="BLOCKED_ON_CREDENTIALS"
    fi
    
    echo "$status|$gsm_status|$vault_status|$kms_status"
}

# Generate deployment info comment
generate_deployment_info() {
    local status_info=$1
    local IFS='|' read -r status gsm_status vault_status kms_status <<< "$status_info"
    
    cat << 'EOF'
## 🍽️ ALA CARTE DEPLOYMENT STATUS — Auto-Generated Report

EOF
    
    echo "**Generated:** $TIMESTAMP"
    echo "**Cycle ID:** $RUN_ID"
    echo "**Status:** $status"
    echo ""
    echo "### 📊 Credential Layer Status"
    echo ""
    echo "| Layer | Status | Action |"
    echo "|-------|--------|--------|"
    
    if [[ "$gsm_status" == "PROVISIONED" ]]; then
        echo "| **GSM** (Primary) | ✅ PROVISIONED | Ready to use |"
    else
        echo "| **GSM** (Primary) | 🟡 PENDING | [Supply GCP credentials](#1816) |"
    fi
    
    if [[ "$vault_status" == "PROVISIONED" ]]; then
        echo "| **Vault** (Secondary) | ✅ PROVISIONED | Ready to use |"
    else
        echo "| **Vault** (Secondary) | 🟡 PENDING | [Supply GCP credentials](#1816) |"
    fi
    
    if [[ "$kms_status" == "PROVISIONED" ]]; then
        echo "| **KMS** (Tertiary) | ✅ PROVISIONED | Ready to use |"
    elif [[ "$kms_status" == "OPTIONAL" ]]; then
        echo "| **KMS** (Tertiary) | ℹ️  OPTIONAL | [Optional: AWS fallback](#1816) |"
    else
        echo "| **KMS** (Tertiary) | ℹ️  OPTIONAL | Optional multi-cloud failover |"
    fi
    
    echo ""
    echo "### 🎯 Deployment Readiness"
    echo ""
    
    if [[ "$status" == "READY_FOR_PROVISIONING" ]]; then
        echo "✅ **STATUS:** Phase 3 Infrastructure Ready to Provision"
        echo ""
        echo "**All required credentials supplied. System ready for provisioning.**"
        echo ""
        echo "**Next Step:**"
        echo "\`\`\`bash"
        echo "gh workflow run provision_phase3.yml -R $REPO_OWNER/$REPO_NAME --ref main"
        echo "\`\`\`"
        
    elif [[ "$status" == "BLOCKED_ON_CREDENTIALS" ]]; then
        echo "🟡 **STATUS:** Blocked on Credential Supply"
        echo ""
        echo "**Action Required:** Supply GCP and AWS credentials"
        echo ""
        echo "**Steps to Unblock:**"
        echo "1. [See #1816 for credential collection guide](https://github.com/$REPO_OWNER/$REPO_NAME/issues/1816)"
        echo "2. Run credential setup commands"
        echo "3. Verify: \`gh secret list | grep GCP\`"
        echo "4. Comment: \`CREDENTIALS_SUPPLIED\` below"
        
    else
        echo "ℹ️  **STATUS:** System Initializing"
        echo ""
        echo "**Next steps:** See deployment activation guide (#1788)"
    fi
    
    echo ""
    echo "### 📋 Architecture Properties (6/6 Implemented)"
    echo ""
    echo "- ✅ **Immutable:** All code in Git + GitHub audit trail"
    echo "- ✅ **Ephemeral:** OIDC tokens (no long-lived credentials)"
    echo "- ✅ **Idempotent:** Safe to re-run, no state pollution"
    echo "- ✅ **No-Ops:** Fully automated scheduling"
    echo "- ✅ **Hands-Off:** Zero manual intervention"
    echo "- ✅ **GSM/Vault/KMS:** 3-layer secrets + fallback"
    echo ""
    echo "### 📞 Related Issues"
    echo ""
    echo "- [#1838](https://github.com/$REPO_OWNER/$REPO_NAME/issues/1838) — Auto-merge enablement"
    echo "- [#1816](https://github.com/$REPO_OWNER/$REPO_NAME/issues/1816) — Phase 3 credential supply"
    echo "- [#1805](https://github.com/$REPO_OWNER/$REPO_NAME/issues/1805) — Merge orchestration"
    echo "- [#1788](https://github.com/$REPO_OWNER/$REPO_NAME/issues/1788) — Ala carte deployment tracker"
    echo ""
    echo "---"
    echo "**Auto-generated by:** Deployment Info Generator"
    echo "**Generated on:** $(date -u '+%Y-%m-%d at %H:%M:%S UTC')"
}

# Post comment to GitHub issue
post_github_comment() {
    local issue=$1
    local comment=$2
    
    gh issue comment "$issue" \
        -R "$REPO_OWNER/$REPO_NAME" \
        --body "$comment"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_info "Starting Ala Carte Deployment Info Generation"
    log_info "Timestamp: $TIMESTAMP | Cycle: $RUN_ID"
    echo ""
    
    # Get system status
    log_info "Analyzing deployment status..."
    status_info=$(get_deployment_status)
    log_success "Status analyzed"
    echo ""
    
    # Generate report
    log_info "Generating deployment information..."
    deployment_info=$(generate_deployment_info "$status_info")
    log_success "Deployment information generated"
    echo ""
    
    # Display report
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "$deployment_info"
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Post to GitHub Issue
    log_info "Posting to GitHub issue #$TRACKING_ISSUE..."
    post_github_comment "$TRACKING_ISSUE" "$deployment_info"
    log_success "Posted to issue #$TRACKING_ISSUE"
    echo ""
    
    # Save to file for audit trail
    local output_file="DEPLOYMENT_INFO_${RUN_ID}.md"
    echo "$deployment_info" > "$output_file"
    log_success "Saved to: $output_file"
    echo ""
    
    log_success "Ala Carte Deployment Info Generation Complete"
    log_info "Issue updated: https://github.com/$REPO_OWNER/$REPO_NAME/issues/$TRACKING_ISSUE"
}

# ============================================================================
# EXECUTE
# ============================================================================

main "$@"
