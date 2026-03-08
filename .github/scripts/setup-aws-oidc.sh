#!/bin/bash
#
# idempotent AWS OIDC Provider Setup
# Configures AWS OIDC for GitHub Actions authentication
#

set -euo pipefail

ACCOUNT_ID="${1:-}"
LOG_DIR="${2:-.setup-logs}"
DRY_RUN="${3:-false}"

if [[ -z "$ACCOUNT_ID" ]]; then
    echo "Error: ACCOUNT_ID required"
    exit 1
fi

mkdir -p "$LOG_DIR"
SETUP_LOG="${LOG_DIR}/aws-oidc-setup-$(date +%s).log"

{
    echo "=== AWS OIDC Provider Setup ==="
    echo "Account ID: $ACCOUNT_ID"
    echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --account-id)
                ACCOUNT_ID="$2"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Function: Create/verify OIDC provider (idempotent)
    ensure_oidc_provider() {
        local account="$1"
        
        echo "Checking OIDC provider..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would ensure OIDC provider exists"
            return
        fi
        
        # Check if provider exists
        EXISTING=$(aws iam list-open-id-connect-providers \
            --query "OpenIDConnectProviderList[?OpenIDConnectProviderArn | contains('token.actions.githubusercontent.com')].OpenIDConnectProviderArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING" ]]; then
            echo "OIDC provider already exists: $EXISTING"
            echo "$EXISTING"
            return
        fi
        
        echo "Creating OIDC provider..."
        
        # Get GitHub OIDC thumbprint
        THUMBPRINT=$(echo | openssl s_client -servername token.actions.githubusercontent.com \
            -showcerts -connect token.actions.githubusercontent.com:443 2>/dev/null | \
            openssl x509 -fingerprint -noout | \
            sed 's/SHA1 Fingerprint=//g' | sed 's/://g' | tr '[:upper:]' '[:lower:]')
        
        # Create OIDC provider
        PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
            --url "https://token.actions.githubusercontent.com" \
            --client-id-list "sts.amazonaws.com" \
            --thumbprint-list "$THUMBPRINT" \
            --query 'OpenIDConnectProviderArn' \
            --output text)
        
        echo "Created OIDC provider: $PROVIDER_ARN"
        echo "$PROVIDER_ARN"
    }
    
    # Function: Create/update GitHub Actions IAM role (idempotent)
    create_github_role() {
        local account="$1"
        
        echo "Checking GitHub Actions IAM role..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create GitHub Actions role"
            return
        fi
        
        ROLE_NAME="github-actions-role"
        
        # Check if role exists
        EXISTING=$(aws iam get-role --role-name "$ROLE_NAME" \
            --query 'Role.Arn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING" ]]; then
            echo "Role already exists: $EXISTING"
            echo "$EXISTING"
            return
        fi
        
        echo "Creating GitHub Actions IAM role..."
        
        # Trust policy for GitHub OIDC
        TRUST_POLICY=$(cat <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:kushin77/self-hosted-runner:*"
        }
      }
    }
  ]
}
EOF
)
        
        TRUST_POLICY="${TRUST_POLICY//ACCOUNT_ID/$account}"
        
        ROLE_ARN=$(aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --query 'Role.Arn' \
            --output text)
        
        echo "Created role: $ROLE_ARN"
        echo "$ROLE_ARN"
    }
    
    # Function: Attach policies to role (idempotent)
    attach_role_policies() {
        local role_name="$1"
        
        echo "Attaching policies to role..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would attach policies"
            return
        fi
        
        # Policies to attach
        local policies=(
            "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
            "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            echo "  - Attaching $policy..."
            aws iam attach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" 2>/dev/null || echo "    (may already exist)"
        done
    }
    
    # Main orchestration
    PROVIDER_ARN=$(ensure_oidc_provider "$ACCOUNT_ID")
    ROLE_ARN=$(create_github_role "$ACCOUNT_ID")
    ROLE_NAME=$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')
    attach_role_policies "$ROLE_NAME"
    
    # Output configuration
    echo ""
    echo "=== AWS OIDC Setup Complete ==="
    echo "OIDC Provider: $PROVIDER_ARN"
    echo "IAM Role: $ROLE_ARN"
    echo ""
    echo "Use this in GitHub Secrets:"
    echo "  AWS_ROLE_TO_ASSUME=$ROLE_ARN"
    
    # Save output
    echo "$PROVIDER_ARN" > "${LOG_DIR}/aws-provider-arn.txt"
    echo "$ROLE_ARN" > "${LOG_DIR}/aws-role-arn.txt"

} | tee "$SETUP_LOG"

echo "Setup log saved to: $SETUP_LOG"
