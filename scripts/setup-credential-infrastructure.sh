#!/bin/bash

###############################################################################
# Master Orchestration: Complete Infrastructure Setup
# 
# This script runs all three credential infrastructure setup scripts:
# 1. GCP Workload Identity Federation
# 2. AWS OIDC Provider
# 3. Vault JWT Auth
#
# Usage: ./setup-credential-infrastructure.sh [--skip-gcp] [--skip-aws] [--skip-vault]
###############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
log_header() {
    echo ""
    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} $1"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_section() {
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
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
# MAIN SETUP
###############################################################################

log_header "🔐 Phase 1A: Complete Credential Infrastructure Setup"

echo "This script will set up:"
echo "  1. GCP Workload Identity Federation (~30 min)"
echo "  2. AWS OIDC Provider (~30 min)"
echo "  3. Vault JWT Auth (~20 min)"
echo ""

# Parse arguments
SKIP_GCP=false
SKIP_AWS=false
SKIP_VAULT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-gcp) SKIP_GCP=true; shift ;;
        --skip-aws) SKIP_AWS=true; shift ;;
        --skip-vault) SKIP_VAULT=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Summary of what will run
echo "Setup Plan:"
[[ "$SKIP_GCP" == false ]] && echo "  ✓ GCP WIF" || echo "  ⊘ GCP WIF (skipped)"
[[ "$SKIP_AWS" == false ]] && echo "  ✓ AWS OIDC" || echo "  ⊘ AWS OIDC (skipped)"
[[ "$SKIP_VAULT" == false ]] && echo "  ✓ Vault JWT" || echo "  ⊘ Vault JWT (skipped)"
echo ""

read -p "Proceed? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "Setup cancelled"
    exit 0
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arrays for outputs
declare -a CREATED_RESOURCES
declare -a OUTPUT_FILES

###############################################################################
# STEP 1: GCP Setup
###############################################################################

if [[ "$SKIP_GCP" == false ]]; then
    log_section "Step 1: GCP Workload Identity Federation Setup"
    
    if [[ ! -f "$SCRIPT_DIR/setup-gcp-wif.sh" ]]; then
        log_error "setup-gcp-wif.sh not found at $SCRIPT_DIR"
        exit 1
    fi
    
    # Run GCP setup
    if bash "$SCRIPT_DIR/setup-gcp-wif.sh"; then
        log_success "GCP WIF setup completed"
        OUTPUT_FILES+=("/tmp/gcp-wif-credentials.txt")
        CREATED_RESOURCES+=("GCP WIF Provider")
    else
        log_error "GCP WIF setup failed. Check errors above."
        exit 1
    fi
else
    log_warning "Skipping GCP WIF setup"
fi

###############################################################################
# STEP 2: AWS Setup
###############################################################################

if [[ "$SKIP_AWS" == false ]]; then
    log_section "Step 2: AWS OIDC Provider Setup"
    
    if [[ ! -f "$SCRIPT_DIR/setup-aws-oidc.sh" ]]; then
        log_error "setup-aws-oidc.sh not found at $SCRIPT_DIR"
        exit 1
    fi
    
    # Run AWS setup
    if bash "$SCRIPT_DIR/setup-aws-oidc.sh"; then
        log_success "AWS OIDC setup completed"
        OUTPUT_FILES+=("/tmp/aws-oidc-credentials.txt")
        CREATED_RESOURCES+=("AWS OIDC Provider")
        CREATED_RESOURCES+=("AWS IAM Role")
    else
        log_error "AWS OIDC setup failed. Check errors above."
        exit 1
    fi
else
    log_warning "Skipping AWS OIDC setup"
fi

###############################################################################
# STEP 3: Vault Setup
###############################################################################

if [[ "$SKIP_VAULT" == false ]]; then
    log_section "Step 3: Vault JWT Auth Setup"
    
    if [[ ! -f "$SCRIPT_DIR/setup-vault-jwt.sh" ]]; then
        log_error "setup-vault-jwt.sh not found at $SCRIPT_DIR"
        exit 1
    fi
    
    # Run Vault setup
    if bash "$SCRIPT_DIR/setup-vault-jwt.sh"; then
        log_success "Vault JWT setup completed"
        OUTPUT_FILES+=("/tmp/vault-jwt-credentials.txt")
        CREATED_RESOURCES+=("Vault JWT Auth")
    else
        log_error "Vault JWT setup failed. Check errors above."
        exit 1
    fi
else
    log_warning "Skipping Vault JWT setup"
fi

###############################################################################
# CONSOLIDATE OUTPUTS
###############################################################################

log_section "Consolidating Credentials"

CONSOLIDATED_FILE="/tmp/credential-infrastructure-setup.txt"

cat > "$CONSOLIDATED_FILE" <<'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                   CREDENTIAL INFRASTRUCTURE SETUP COMPLETE                 ║
║                                                                            ║
║      All authentication methods are now configured for GitHub Actions      ║
╚════════════════════════════════════════════════════════════════════════════╝

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

═══════════════════════════════════════════════════════════════════════════════
📋 GITHUB SECRETS TO CREATE
═══════════════════════════════════════════════════════════════════════════════

Run these commands to add secrets to your GitHub repository:

EOF

# Add secrets from each output file
for output_file in "${OUTPUT_FILES[@]}"; do
    if [[ -f "$output_file" ]]; then
        echo "" >> "$CONSOLIDATED_FILE"
        echo "# From: $(basename $output_file)" >> "$CONSOLIDATED_FILE"
        echo "# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$CONSOLIDATED_FILE"
        
        # Extract secret creation commands
        grep "gh secret set" "$output_file" >> "$CONSOLIDATED_FILE" 2>/dev/null || true
    fi
done

# Add full details at the end
cat >> "$CONSOLIDATED_FILE" <<'EOF'

═══════════════════════════════════════════════════════════════════════════════
📂 DETAILED CONFIGURATION FILES
═══════════════════════════════════════════════════════════════════════════════

EOF

for output_file in "${OUTPUT_FILES[@]}"; do
    if [[ -f "$output_file" ]]; then
        echo "" >> "$CONSOLIDATED_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$CONSOLIDATED_FILE"
        echo "File: $(basename $output_file)" >> "$CONSOLIDATED_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$CONSOLIDATED_FILE"
        echo "" >> "$CONSOLIDATED_FILE"
        cat "$output_file" >> "$CONSOLIDATED_FILE"
    fi
done

log_success "Consolidated credentials saved to: $CONSOLIDATED_FILE"

###############################################################################
# FINAL SUMMARY
###############################################################################

log_header "✅ Phase 1A Infrastructure Setup COMPLETE!"

echo "Created Resources:"
for resource in "${CREATED_RESOURCES[@]}"; do
    echo "  ✓ $resource"
done
echo ""

echo "Output Files:"
for file in "${OUTPUT_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        SIZE=$(wc -l < "$file")
        echo "  📄 $(basename $file) ($SIZE lines)"
    fi
done
echo ""

echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "📋 NEXT STEPS:"
echo ""
echo "1. Review consolidated credentials:"
echo "   cat $CONSOLIDATED_FILE"
echo ""
echo "2. Create GitHub secrets (run these commands):"
echo "   $(grep 'gh secret set' $CONSOLIDATED_FILE | head -1)"
echo "   # ... (see file for complete list)"
echo ""
echo "3. Verify credentials stored:"
echo "   gh secret list --repo kushin77/self-hosted-runner"
echo ""
echo "4. Start Phase 1A execution:"
echo "   - Day 1 (Tuesday): GSM secret migration"
echo "   - Day 2 (Wednesday): Vault secret setup"
echo "   - Day 3 (Thursday): Helper action testing"
echo "   - Day 4-5 (Friday): Rotation integration + compliance audit"
echo ""
echo "5. Reference: docs/PHASE_1A_EXECUTION_GUIDE.md"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

log_success "Setup complete! Infrastructure ready for Phase 1A execution."
