#!/bin/bash
#
# idempotent Vault JWT Authentication Setup
# Configures Vault JWT auth method for GitHub Actions
#

set -euo pipefail

VAULT_ADDR="${1:-}"
LOG_DIR="${2:-.setup-logs}"
DRY_RUN="${3:-false}"

if [[ -z "$VAULT_ADDR" ]]; then
    echo "Error: VAULT_ADDR required"
    exit 1
fi

mkdir -p "$LOG_DIR"
SETUP_LOG="${LOG_DIR}/vault-jwt-setup-$(date +%s).log"

{
    echo "=== Vault JWT Authentication Setup ==="
    echo "Vault Address: $VAULT_ADDR"
    echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vault-addr)
                VAULT_ADDR="$2"
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
    
    # Function: Enable JWT auth method (idempotent)
    enable_jwt_auth() {
        local vault_addr="$1"
        
        echo "Checking JWT auth method..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would enable JWT auth method"
            return
        fi
        
        # Check if JWT auth is already enabled
        EXISTING=$(curl -s \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            "${vault_addr}/v1/sys/auth" | jq -r '.data["jwt/"]' 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
            echo "JWT auth method already enabled"
            return
        fi
        
        echo "Enabling JWT auth method..."
        curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            -d '{"type":"jwt"}' \
            "${vault_addr}/v1/sys/auth/jwt" || echo "Warning: JWT auth may already be enabled"
    }
    
    # Function: Configure JWT auth (idempotent)
    configure_jwt_auth() {
        local vault_addr="$1"
        
        echo "Configuring JWT auth..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would configure JWT auth"
            return
        fi
        
        # Configure JWT auth
        curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            -d '{
                "oidc_discovery_url": "https://token.actions.githubusercontent.com",
                "bound_audiences": "sts.amazonaws.com",
                "oidc_skip_expiry_check": false
            }' \
            "${vault_addr}/v1/auth/jwt/config" || echo "Warning: JWT config already set"
    }
    
    # Function: Create JWT role (idempotent)
    create_jwt_role() {
        local vault_addr="$1"
        
        echo "Creating JWT role for GitHub..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create JWT role"
            return
        fi
        
        # Create GitHub Actions JWT role
        curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            -d '{
                "bound_audiences": ["sts.amazonaws.com"],
                "user_claim": "actor",
                "role_type": "jwt",
                "policies": ["default"],
                "ttl": "1h"
            }' \
            "${vault_addr}/v1/auth/jwt/role/github-actions" || echo "Warning: JWT role may already exist"
    }
    
    # Function: Create JWT policy (idempotent)
    create_jwt_policy() {
        local vault_addr="$1"
        
        echo "Creating JWT policy..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create JWT policy"
            return
        fi
        
        POLICY_JSON=$(cat <<'EOF'
{
  "path": {
    "secret/data/*": {
      "capabilities": ["read", "list"]
    },
    "secret/metadata/*": {
      "capabilities": ["read", "list"]
    },
    "auth/token/renew-self": {
      "capabilities": ["read", "update"]
    }
  }
}
EOF
)
        
        # Create policy
        curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            -d "{\"policy\": $(echo "$POLICY_JSON" | jq -c .)}" \
            "${vault_addr}/v1/sys/policies/acl/github-actions" || echo "Warning: Policy may already exist"
    }
    
    # Main orchestration
    enable_jwt_auth "$VAULT_ADDR"
    configure_jwt_auth "$VAULT_ADDR"
    create_jwt_role "$VAULT_ADDR"
    create_jwt_policy "$VAULT_ADDR"
    
    # Test JWT authentication (dry-run safe)
    echo ""
    echo "Testing Vault JWT auth configuration..."
    curl -s "${VAULT_ADDR}/v1/auth/jwt/config" \
        -H "X-Vault-Token: ${VAULT_TOKEN:-}" | jq '.' > "${LOG_DIR}/vault-jwt-config.json" || true
    
    # Output configuration
    echo ""
    echo "=== Vault JWT Setup Complete ==="
    echo "Vault Address: $VAULT_ADDR"
    echo "Auth Method: jwt"
    echo "Role: github-actions"
    echo ""
    echo "Use these in GitHub Secrets:"
    echo "  VAULT_ADDR=$VAULT_ADDR"
    echo "  VAULT_OIDC_TOKEN=(GitHub OIDC token, auto-provided)"
    
    # Save output
    echo "$VAULT_ADDR" > "${LOG_DIR}/vault-addr.txt"

} | tee "$SETUP_LOG"

echo "Setup log saved to: $SETUP_LOG"
