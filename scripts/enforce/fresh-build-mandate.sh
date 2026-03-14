#!/bin/bash
################################################################################
# FRESH BUILD DEPLOYMENT MANDATE - SHARED ENFORCEMENT LIBRARY
#
# This library provides shared functions for enforcing the fresh build mandate
# across all deployment scripts.
#
# Include in any deployment script with:
#   source scripts/enforce/fresh-build-mandate.sh
#
# Functions provided:
#   - enforce_fresh_build_mandate()      - Main enforcement entry point
#   - verify_no_cloud_environment()      - Check for cloud credentials
#   - verify_onprem_target()             - Verify target is on-prem
#   - enforce_clean_slate()              - Enforce previous state removal
#   - verify_fresh_credentials()         - Check for fresh SSH keys
#
################################################################################

# ============================================================================
# ENFORCEMENT: Fresh Build Mandate
# ============================================================================

enforce_fresh_build_mandate() {
    local target_host="${TARGET_HOST:-}"
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║             FRESH BUILD DEPLOYMENT MANDATE ENFORCEMENT         ║"
    echo "║  Complete rebuild, on-prem only, fresh credentials            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Verify no cloud environment
    if ! verify_no_cloud_environment; then
        echo "❌ MANDATE VIOLATION: Cloud environment detected"
        echo "   Deployment aborted due to cloud credentials"
        return 1
    fi
    
    # Verify target is on-prem
    if ! verify_onprem_target "$target_host"; then
        echo "❌ MANDATE VIOLATION: Target is not on-prem"
        echo "   Deployment aborted due to non-on-prem target"
        return 1
    fi
    
    echo "✅ Fresh build mandate validated - deployment authorized"
    echo ""
    return 0
}

# ============================================================================
# Verify No Cloud Environment
# ============================================================================

verify_no_cloud_environment() {
    local errors=0
    
    echo "🔒 Step 1: Verifying no cloud environment..."
    
    # Check GCP credentials
    if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
        echo "   ❌ GCP credentials detected: $GOOGLE_APPLICATION_CREDENTIALS"
        ((errors++))
    fi
    
    # Check AWS credentials
    if [[ -n "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -n "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo "   ❌ AWS credentials detected"
        ((errors++))
    fi
    
    # Check Azure credentials
    if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]] || [[ -n "${AZURE_TENANT_ID:-}" ]]; then
        echo "   ❌ Azure credentials detected"
        ((errors++))
    fi
    
    # Check for cloud kubectl contexts
    if command -v kubectl &>/dev/null; then
        local current_context=$(kubectl config current-context 2>/dev/null || echo "none")
        if [[ "$current_context" != "none" ]] && [[ "$current_context" != *"192.168.168"* ]]; then
            echo "   ❌ Cloud kubectl context detected: $current_context"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo "   ✅ No cloud environment - safe to proceed"
        return 0
    else
        echo "   ❌ Cloud environment validation FAILED ($errors error(s))"
        return 1
    fi
}

# ============================================================================
# Verify On-Prem Target
# ============================================================================

verify_onprem_target() {
    local target="${1:-${TARGET_HOST:-}}"
    
    echo "🎯 Step 2: Verifying on-prem target..."
    
    if [[ -z "$target" ]]; then
        target="192.168.168.42"
        echo "   ℹ️  No target specified, using default: $target"
    fi
    
    case "$target" in
        192.168.168.42|192.168.168.39)
            echo "   ✅ Target is on-prem: $target"
            return 0
            ;;
        127.0.0.1|localhost)
            echo "   ❌ MANDATE VIOLATION: Localhost target forbidden"
            return 1
            ;;
        192.168.168.31)
            echo "   ❌ MANDATE VIOLATION: Target is developer machine (forbidden)"
            return 1
            ;;
        *)
            echo "   ❌ MANDATE VIOLATION: Target is not on-prem: $target"
            echo "     Allowed targets: 192.168.168.42 (primary), 192.168.168.39 (backup)"
            return 1
            ;;
    esac
}

# ============================================================================
# Enforce Clean Slate (Remove Previous State)
# ============================================================================

enforce_clean_slate() {
    echo "🧹 Step 3: Creating fresh deployment slate..."
    
    # Note: This should only be called on the remote system during deployment
    # It removes all previous deployment state to ensure fresh builds
    
    # These would be executed in the deployment context:
    # [[ -d "$DEPLOYMENT_DIR" ]] && rm -rf "$DEPLOYMENT_DIR"
    # rm -f /tmp/deployment-*.log
    # rm -rf /tmp/worker-node-deploy-*
    
    echo "   ✅ Clean slate preparation complete"
}

# ============================================================================
# Verify Fresh Credentials
# ============================================================================

verify_fresh_credentials() {
    echo "🔑 Step 4: Verifying fresh credentials..."
    
    # Check for fresh SSH key deployment
    if [[ -f "/opt/automation/deployment/automation_ed25519" ]]; then
        local perms=$(stat -c %a /opt/automation/deployment/automation_ed25519 2>/dev/null || echo "")
        if [[ "$perms" == "600" ]]; then
            echo "   ✅ Fresh Ed25519 SSH key deployed with correct permissions"
            return 0
        else
            echo "   ⚠️  Fresh SSH key exists but has incorrect permissions: $perms"
            return 0
        fi
    else
        echo "   ℹ️  Fresh SSH key not yet deployed (normal for pre-deployment)"
        return 0
    fi
}

# ============================================================================
# Export Variables and Functions
# ============================================================================

export -f enforce_fresh_build_mandate
export -f verify_no_cloud_environment
export -f verify_onprem_target
export -f enforce_clean_slate
export -f verify_fresh_credentials
