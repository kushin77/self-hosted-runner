#!/bin/bash

###############################################################################
# QUICK START: Run All Credential Infrastructure Setup Scripts
# 
# This is the fastest way to set up GCP/AWS/Vault for Phase 1A
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}"
cat <<'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║    🔐 Phase 1A: Credential Infrastructure Setup - QUICK START             ║
║                                                                            ║
║    This script will guide you through setting up:                         ║
║      1. GCP Workload Identity Federation (~30 min)                        ║
║      2. AWS OIDC Provider (~30 min)                                       ║
║      3. Vault JWT Auth (~20 min)                                          ║
║                                                                            ║
║    Total time: ~80 minutes (can run in parallel)                          ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝

EOF
echo -e "${NC}"

echo "Prerequisites:"
echo "  ✓ gcloud CLI (for GCP)"
echo "  ✓ aws CLI (for AWS)"
echo "  ✓ curl & jq (for Vault)"
echo "  ✓ Proper credentials for each system"
echo ""

read -p "Ready to proceed? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Setup cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Checking if scripts exist...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in setup-gcp-wif.sh setup-aws-oidc.sh setup-vault-jwt.sh setup-credential-infrastructure.sh; do
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        echo -e "${RED}Error: $script not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ All setup scripts found${NC}"
echo ""

echo "Running master orchestration script..."
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"

bash "$SCRIPT_DIR/setup-credential-infrastructure.sh"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Review credentials: cat /tmp/credential-infrastructure-setup.txt"
echo "  2. Create GitHub secrets with the provided commands"
echo "  3. Verify secrets created: gh secret list"
echo "  4. Start Phase 1A execution (see PHASE_1A_EXECUTION_GUIDE.md)"
echo ""
