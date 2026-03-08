#!/bin/bash
#
# Auto-discover GCP Project ID, AWS Account ID, and Vault details
# Idempotent credential discovery for cloud providers
# Used by Phase 2 OIDC/WIF setup to minimize manual input
#

set -euo pipefail

DISCOVERY_LOG="${1:-.setup-logs/credential-discovery.log}"
OUTPUT_FILE="${2:-.setup-logs/discovered-credentials.json}"
DRY_RUN="${3:-false}"

mkdir -p "$(dirname "$DISCOVERY_LOG")"
mkdir -p "$(dirname "$OUTPUT_FILE")"

{
    echo "=== Cloud Credential Discovery ==="
    echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Initialize JSON output
    declare -A credentials
    credentials[gcp_project_id]=""
    credentials[aws_account_id]=""
    credentials[vault_addr]=""
    credentials[vault_namespace]="root"
    credentials[discovery_method]="auto"
    
    # === GCP AUTO-DISCOVERY ===
    echo "--- Attempting GCP Project ID Discovery ---"
    
    # Method 1: Check gcloud CLI
    if command -v gcloud &> /dev/null; then
        gcp_project=$(gcloud config get-value project 2>/dev/null || true)
        if [[ -n "$gcp_project" ]]; then
            echo "✓ GCP Project ID discovered via gcloud: $gcp_project"
            credentials[gcp_project_id]="$gcp_project"
            credentials[gcp_discovery_method]="gcloud-config"
        else
            echo "⚠ gcloud installed but no project configured"
        fi
    else
        echo "⚠ gcloud CLI not found"
    fi
    
    # Method 2: Check APPLICATION_CREDENTIALS
    if [[ -z "${credentials[gcp_project_id]}" ]]; then
        if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
            if [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
                gcp_project=$(jq -r '.project_id // empty' "$GOOGLE_APPLICATION_CREDENTIALS" 2>/dev/null || true)
                if [[ -n "$gcp_project" ]]; then
                    echo "✓ GCP Project ID from GOOGLE_APPLICATION_CREDENTIALS: $gcp_project"
                    credentials[gcp_project_id]="$gcp_project"
                    credentials[gcp_discovery_method]="service-account-json"
                fi
            fi
        fi
    fi
    
    # Method 3: Check GitHub secrets/environment variables
    if [[ -z "${credentials[gcp_project_id]}" ]]; then
        if [[ -n "${GCP_PROJECT_ID:-}" ]]; then
            echo "✓ GCP Project ID from environment: $GCP_PROJECT_ID"
            credentials[gcp_project_id]="$GCP_PROJECT_ID"
            credentials[gcp_discovery_method]="environment-variable"
        fi
    fi
    
    if [[ -z "${credentials[gcp_project_id]}" ]]; then
        echo "⚠ GCP Project ID not auto-discovered - will need to be provided manually"
    fi
    
    echo ""
    
    # === AWS AUTO-DISCOVERY ===
    echo "--- Attempting AWS Account ID Discovery ---"
    
    # Method 1: Check AWS STS
    if command -v aws &> /dev/null; then
        if [[ -n "${AWS_PROFILE:-}" ]] || [[ -e ~/.aws/credentials ]]; then
            aws_account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
            if [[ -n "$aws_account" && "$aws_account" != "None" ]]; then
                echo "✓ AWS Account ID discovered via STS: $aws_account"
                credentials[aws_account_id]="$aws_account"
                credentials[aws_discovery_method]="sts"
            else
                echo "⚠ AWS CLI installed but not authenticated"
            fi
        fi
    else
        echo "⚠ AWS CLI not found"
    fi
    
    # Method 2: Check environment variable
    if [[ -z "${credentials[aws_account_id]}" ]]; then
        if [[ -n "${AWS_ACCOUNT_ID:-}" ]]; then
            echo "✓ AWS Account ID from environment: $AWS_ACCOUNT_ID"
            credentials[aws_account_id]="$AWS_ACCOUNT_ID"
            credentials[aws_discovery_method]="environment-variable"
        fi
    fi
    
    # Method 3: Parse from assume-role ARN if available
    if [[ -z "${credentials[aws_account_id]}" ]]; then
        if [[ -n "${AWS_ROLE_ARN:-}" ]]; then
            aws_account=$(echo "$AWS_ROLE_ARN" | sed 's|.*:iam::\([0-9]\+\):.*|\1|')
            if [[ "$aws_account" =~ ^[0-9]{12}$ ]]; then
                echo "✓ AWS Account ID from ARN: $aws_account"
                credentials[aws_account_id]="$aws_account"
                credentials[aws_discovery_method]="arn-parsing"
            fi
        fi
    fi
    
    if [[ -z "${credentials[aws_account_id]}" ]]; then
        echo "⚠ AWS Account ID not auto-discovered - will need to be provided manually"
    fi
    
    echo ""
    
    # === VAULT AUTO-DISCOVERY ===
    echo "--- Attempting Vault Discovery ---"
    
    # Method 1: Check VAULT_ADDR environment variable
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        echo "✓ Vault address from environment: $VAULT_ADDR"
        credentials[vault_addr]="$VAULT_ADDR"
        credentials[vault_discovery_method]="environment-variable"
    fi
    
    # Method 2: Check GitHub secret (common storage)
    if [[ -z "${credentials[vault_addr]}" ]]; then
        if [[ -n "${VAULT_ADDR_FROM_SECRET:-}" ]]; then
            echo "✓ Vault address from secret: $VAULT_ADDR_FROM_SECRET"
            credentials[vault_addr]="$VAULT_ADDR_FROM_SECRET"
            credentials[vault_discovery_method]="secret"
        fi
    fi
    
    # Method 3: Check vault CLI
    if [[ -z "${credentials[vault_addr]}" ]]; then
        if command -v vault &> /dev/null; then
            vault_addr=$(vault status 2>/dev/null | grep "Cluster Name" | head -1 || true)
            if [[ -n "$vault_addr" ]]; then
                echo "✓ Vault detected via CLI"
                credentials[vault_discovery_method]="vault-cli"
            fi
        fi
    fi
    
    if [[ -z "${credentials[vault_addr]}" ]]; then
        echo "⚠ Vault address not auto-discovered - will need to be provided manually"
    fi
    
    # Check for namespace
    if [[ -n "${VAULT_NAMESPACE:-}" ]]; then
        echo "✓ Vault namespace discovered: $VAULT_NAMESPACE"
        credentials[vault_namespace]="$VAULT_NAMESPACE"
    fi
    
    echo ""
    echo "=== Discovery Summary ==="
    echo "GCP Project ID: ${credentials[gcp_project_id]:-[NOT DISCOVERED]}"
    echo "AWS Account ID: ${credentials[aws_account_id]:-[NOT DISCOVERED]}"
    echo "Vault Address: ${credentials[vault_addr]:-[NOT DISCOVERED]}"
    echo "Vault Namespace: ${credentials[vault_namespace]}"
    echo ""
    
    # === OUTPUT JSON ===
    echo "Writing discovered credentials to: $OUTPUT_FILE"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$OUTPUT_FILE" << JSONEOF
{
  "discovered_credentials": {
    "gcp_project_id": "${credentials[gcp_project_id]}",
    "gcp_discovery_method": "${credentials[gcp_discovery_method]:-unknown}",
    "aws_account_id": "${credentials[aws_account_id]}",
    "aws_discovery_method": "${credentials[aws_discovery_method]:-unknown}",
    "vault_addr": "${credentials[vault_addr]}",
    "vault_namespace": "${credentials[vault_namespace]}",
    "vault_discovery_method": "${credentials[vault_discovery_method]:-unknown}",
    "discovery_timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "discovery_host": "$(hostname 2>/dev/null || echo 'unknown')",
    "discovery_method": "auto-discovery"
  },
  "manual_input_required": {
    "gcp_project_id": $([ -z "${credentials[gcp_project_id]}" ] && echo "true" || echo "false"),
    "aws_account_id": $([ -z "${credentials[aws_account_id]}" ] && echo "true" || echo "false"),
    "vault_addr": $([ -z "${credentials[vault_addr]}" ] && echo "true" || echo "false")
  },
  "next_steps": [
    "Review discovered credentials above",
    "Provide any missing credentials (marked as manual_input_required)",
    "Run setup-oidc-infrastructure.yml with discovered + manual credentials",
    "All operations are idempotent and repeatable"
  ]
}
JSONEOF
        
        echo "✓ Credentials written to JSON"
        echo ""
        echo "Discovered credentials (JSON):"
        cat "$OUTPUT_FILE" | jq '.' 2>/dev/null || cat "$OUTPUT_FILE"
    else
        echo "✓ Dry run mode - no files written"
    fi
    
    echo ""
    echo "=== Auto-Discovery Complete ==="
    
} | tee "$DISCOVERY_LOG"

echo "Discovery log saved to: $DISCOVERY_LOG"
echo "Credentials file: $OUTPUT_FILE"
