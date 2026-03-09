#!/bin/bash
#
# GitHub Secrets Provisioning Guide & Validation
# Purpose: Ensure all required credentials are properly configured
# Last Updated: 2026-03-09
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  GitHub Repository Secrets - Provisioning Guide${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo

# Step 1: Explain what needs to be done
cat << 'EOF'
🔑 REQUIRED SECRETS (4 total)

These secrets must be added to GitHub repository settings to enable Phase 2 validation.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1️⃣  VAULT_ADDR
    Type: URL
    Value: https://<vault-server>:8200  (or http://localhost:8200 for local)
    Purpose: HashiCorp Vault server endpoint for credential retrieval
    Example: https://vault.company.com:8200

2️⃣  VAULT_ROLE
    Type: String
    Value: <your-vault-role-id>
    Purpose: Vault role ID configured for GitHub Actions OIDC
    Example: github-actions-role

3️⃣  AWS_ROLE_TO_ASSUME
    Type: ARN
    Value: arn:aws:iam::<account-id>:role/<role-name>
    Purpose: AWS IAM role for credential access via OIDC
    Example: arn:aws:iam::123456789012:role/github-actions-role

4️⃣  GCP_WORKLOAD_IDENTITY_PROVIDER
    Type: Resource Name
    Value: projects/<project-id>/locations/global/workloadIdentityPools/<pool-id>/providers/<provider-id>
    Purpose: Google Cloud Workload Identity Federation provider for OIDC
    Example: projects/12345/locations/global/workloadIdentityPools/github-pool/providers/github-provider

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

HOW TO ADD SECRETS TO GITHUB

Option A: Via GitHub Web UI (Recommended for first-time setup)
──────────────────────────────────────────────────────────────

1. Go to your repository: https://github.com/kushin77/self-hosted-runner
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. For each secret:
   - Name: (e.g., VAULT_ADDR)
   - Value: (paste value from above)
   - Click "Add secret"
5. Repeat for all 4 secrets

Option B: Via GitHub CLI (For automation)
──────────────────────────────────────────

# First, ensure you're authenticated
gh auth login

# Then add each secret:
gh secret set VAULT_ADDR --repo kushin77/self-hosted-runner --body "https://vault.company.com:8200"
gh secret set VAULT_ROLE --repo kushin77/self-hosted-runner --body "github-actions-role"
gh secret set AWS_ROLE_TO_ASSUME --repo kushin77/self-hosted-runner --body "arn:aws:iam::123456789012:role/github-actions-role"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --repo kushin77/self-hosted-runner --body "projects/12345/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

Option C: Via GitHub API (For CI/CD integration)
────────────────────────────────────────────────

curl -X PUT \
  -H "Authorization: token <YOUR_GITHUB_TOKEN>" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/kushin77/self-hosted-runner/actions/secrets/VAULT_ADDR \
  -d '{
    "encrypted_value": "<base64-encrypted-value>",
    "key_id": "<key-id-from-repository>"
  }'

EOF

# Step 2: Verify which secrets are already set
echo
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}✅ VERIFICATION: Check which secrets are already configured${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Try to list secrets using gh CLI
if command -v gh &> /dev/null; then
    echo "Using GitHub CLI to check current secrets..."
    echo
    
    # Check each secret
    for secret in VAULT_ADDR VAULT_ROLE AWS_ROLE_TO_ASSUME GCP_WORKLOAD_IDENTITY_PROVIDER; do
        if gh secret list --repo kushin77/self-hosted-runner 2>/dev/null | grep -q "^${secret}"; then
            echo -e "${GREEN}✅ ${secret}${NC} - Already configured"
        else
            echo -e "${YELLOW}⚠️  ${secret}${NC} - NOT configured (needs to be added)"
        fi
    done
    echo
else
    echo -e "${YELLOW}GitHub CLI not found. Install with: brew install gh${NC}"
    echo "Cannot auto-check secrets without gh CLI."
    echo
fi

# Step 3: Provide validation script
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧪 VALIDATION: After adding secrets, run Phase 2 validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

cat << 'EOF'
Once all 4 secrets are added to GitHub:

1. Phase 2 validation workflow triggers automatically:
   • The next 15-min credential rotation cycle will use your secrets
   • Health check will verify all providers (GSM, Vault, KMS) accessible
   • If successful: Green checkmark in GitHub Actions

2. To manually trigger validation:
   • Go to your repo Actions tab
   • Find "Auto Credential Rotation" workflow
   • Click "Run workflow" → "Run workflow"

3. Expected success indicators:
   ✅ Rotation completes without errors
   ✅ Audit logs show successful credential fetches
   ✅ Health check confirms all 3 providers UP
   ✅ No escalation issues created (if all providers up)

4. Check logs:
   • GitHub Actions tab → workflow run
   • Look for: "✅ Credential rotation cycle complete"
   • Or view: Audit logs at .audit-logs/audit-*.jsonl

EOF

# Step 4: Troubleshooting
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔧 TROUBLESHOOTING${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

cat << 'EOF'
If Phase 2 validation fails:

1. Secret Not Recognized
   • Error: "Variable not found: VAULT_ADDR"
   • Solution: Verify secret name spelling is EXACT (case-sensitive)
   • Re-add the secret in GitHub UI if needed

2. Connection Timeout (Vault)
   • Error: "Failed to connect to Vault"
   • Solution: Verify VAULT_ADDR is reachable from GitHub Actions
   • Check if firewall blocks GitHub IPs to your Vault server

3. OIDC Token Exchange Failed
   • Error: "Failed to exchange OIDC token"
   • Solution: Verify Vault/AWS/GCP have GitHub Actions OIDC provider configured
   • Check trust relationships in respective cloud platforms

4. Invalid Role Format
   • Error: "Role not found"
   • Solution: Verify VAULT_ROLE matches exactly what's configured in Vault
   • Use: vault list auth/jwt/roles (if using JWT auth in Vault)

5. AWS IAM Role Not Accessible
   • Error: "Not authorized to assume role"
   • Solution: Verify GitHub OIDC provider is added to AWS trust relationship
   • Trust policy should include: sts:AssumeRoleWithWebIdentity

For detailed help:
  • See: docs/CREDENTIAL_RUNBOOK.md (troubleshooting section)
  • See: docs/DISASTER_RECOVERY.md (all failure modes)
  • See: ON_CALL_QUICK_REFERENCE.md (rapid response)

EOF

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ NEXT STEPS:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "1. Add the 4 secrets to GitHub repository (see above for methods)"
echo "2. Phase 2 validation triggers automatically on next rotation cycle"
echo "3. Monitor GitHub Actions for success/failures"
echo "4. If successful: System is ready for production use"
echo
echo "Reference: https://github.com/kushin77/self-hosted-runner/issues/2042"
echo

