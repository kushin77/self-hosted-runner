#!/bin/bash
#
# Phase 3B: Credential Manager CLI
# Manages credential injection and storage
#
# USAGE:
#   ./scripts/phase3b-credential-manager.sh set-aws --key ID --secret SECRET
#   ./scripts/phase3b-credential-manager.sh set-vault --addr URL --token TOKEN
#   ./scripts/phase3b-credential-manager.sh set-gcp --project PROJECT
#   ./scripts/phase3b-credential-manager.sh get-all
#   ./scripts/phase3b-credential-manager.sh verify
#   ./scripts/phase3b-credential-manager.sh activate
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CRED_STORE="${HOME}/.phase3b-credentials"
AUDIT_FILE="${ROOT_DIR}/logs/deployment-provisioning-audit.jsonl"

mkdir -p "$(dirname "$CRED_STORE")"
mkdir -p "$(dirname "$AUDIT_FILE")"

# Secure storage for credentials (chmod 600)
store_credential() {
    local key=$1
    local value=$2
    
    if [[ -z "$key" || -z "$value" ]]; then
        echo "❌ ERROR: Key and value required"
        return 1
    fi
    
    # Create secure file if doesn't exist
    if [[ ! -f "$CRED_STORE" ]]; then
        touch "$CRED_STORE"
        chmod 600 "$CRED_STORE"
    fi
    
    # Remove existing key if present
    grep -v "^${key}=" "$CRED_STORE" > "$CRED_STORE.tmp" 2>/dev/null || echo "" > "$CRED_STORE.tmp"
    
    # Add new entry
    echo "${key}=${value}" >> "$CRED_STORE.tmp"
    
    # Atomically replace
    mv "$CRED_STORE.tmp" "$CRED_STORE"
    chmod 600 "$CRED_STORE"
    
    echo "✅ Stored: $key"
}

# Retrieve credential
get_credential() {
    local key=$1
    
    if [[ ! -f "$CRED_STORE" ]]; then
        return
    fi
    
    grep "^${key}=" "$CRED_STORE" | cut -d= -f2- || echo ""
}

# Audit credential access
audit_credential_access() {
    local action=$1
    local cred_type=$2
    
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg action "$action" \
      --arg cred_type "$cred_type" \
      '{timestamp: $ts, event: "credential_access", action: $action, credential_type: $cred_type, phase: "3B"}' \
      >> "$AUDIT_FILE"
}

# Command: set-aws
cmd_set_aws() {
    local key="" secret=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --key) key="$2"; shift 2 ;;
            --secret) secret="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$key" || -z "$secret" ]]; then
        echo "❌ ERROR: --key and --secret required"
        return 1
    fi
    
    store_credential "AWS_ACCESS_KEY_ID" "$key"
    store_credential "REDACTED_AWS_SECRET_ACCESS_KEY" "$secret"
    
    # Export to environment
    export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID"
    export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY"
    
    # Verify
    if aws sts get-caller-identity > /dev/null 2>&1; then
        echo "✅ AWS credentials verified"
        audit_credential_access "set" "AWS"
    else
        echo "⚠️ WARNING: AWS credentials appear invalid"
    fi
}

# Command: set-vault
cmd_set_vault() {
    local addr="" token=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --addr) addr="$2"; shift 2 ;;
            --token) token="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$addr" || -z "$token" ]]; then
        echo "❌ ERROR: --addr and --token required"
        return 1
    fi
    
    store_credential "VAULT_ADDR" "$addr"
    store_credential "REDACTED_VAULT_TOKEN" "$token"
    
    # Export to environment
    export VAULT_ADDR="$addr"
    export REDACTED_VAULT_TOKEN="$token"
    
    # Verify
    if vault status > /dev/null 2>&1; then
        echo "✅ Vault connection verified"
        audit_credential_access "set" "Vault"
    else
        echo "⚠️ WARNING: Vault connection failed"
    fi
}

# Command: set-gcp
cmd_set_gcp() {
    local project=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project) project="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [[ -z "$project" ]]; then
        echo "❌ ERROR: --project required"
        return 1
    fi
    
    store_credential "GCP_PROJECT_ID" "$project"
    
    export GCP_PROJECT_ID="$project"
    
    # Verify
    if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
        echo "✅ GCP project set to: $project"
        audit_credential_access "set" "GCP"
    else
        echo "⚠️ WARNING: GCP authentication not available"
    fi
}

# Command: get-all
cmd_get_all() {
    echo "📋 Stored Credentials:"
    echo "====================="
    
    if [[ ! -f "$CRED_STORE" ]]; then
        echo "(none)"
        return
    fi
    
    while IFS= read -r line; do
        key=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)
        
        # Mask secrets in output
        if [[ "$value" =~ ^.{20} ]]; then
            masked="${value:0:8}...${value: -4}"
        else
            masked="***"
        fi
        
        echo "  $key = $masked"
    done < "$CRED_STORE"
}

# Command: verify
cmd_verify() {
    echo "🔍 Verifying Credentials..."
    echo ""
    
    # Load credentials
    if [[ -f "$CRED_STORE" ]]; then
        source "$CRED_STORE"
    fi
    
    # Export them
    export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
    export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
    export VAULT_ADDR=${VAULT_ADDR:-}
    export REDACTED_VAULT_TOKEN=${REDACTED_VAULT_TOKEN:-}
    export GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
    
    local all_ok=1
    
    # Verify each layer
    echo "Layer 1 (GSM):"
    if [[ -n "$GCP_PROJECT_ID" ]]; then
        if gcloud auth list 2>/dev/null | grep -q "ACTIVE"; then
            echo "  ✅ GCP authenticated for project: $GCP_PROJECT_ID"
        else
            echo "  ⚠️ GCP credentials not available"
            all_ok=0
        fi
    else
        echo "  ⏳ Not configured"
    fi
    
    echo "Layer 2A (Vault):"
    if [[ -n "$VAULT_ADDR" && -n "$REDACTED_VAULT_TOKEN" ]]; then
        if vault status > /dev/null 2>&1; then
            echo "  ✅ Vault connected: $VAULT_ADDR"
        else
            echo "  ⚠️ Vault connection failed"
            all_ok=0
        fi
    else
        echo "  ⏳ Not configured"
    fi
    
    echo "Layer 2B (AWS KMS):"
    if [[ -n "$AWS_ACCESS_KEY_ID" && -n "$REDACTED_AWS_SECRET_ACCESS_KEY" ]]; then
        if aws sts get-caller-identity > /dev/null 2>&1; then
            ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
            echo "  ✅ AWS authenticated for account: $ACCOUNT"
        else
            echo "  ⚠️ AWS credentials invalid"
            all_ok=0
        fi
    else
        echo "  ⏳ Not configured"
    fi
    
    echo "Layer 3 (Local Cache):"
    if [[ -d "/var/cache/credentials" ]]; then
        echo "  ✅ Local credential cache available"
    else
        echo "  ⏳ Local cache not configured"
    fi
    
    echo ""
    if [[ $all_ok -eq 0 ]]; then
        echo "⚠️ Some credential layers unavailable"
        return 1
    else
        echo "✅ All configured credentials verified"
        return 0
    fi
}

# Command: activate
cmd_activate() {
    echo "🚀 Activating Phase 3B with stored credentials..."
    echo ""
    
    # Load credentials from storage
    if [[ -f "$CRED_STORE" ]]; then
        source "$CRED_STORE"
    fi
    
    # Export to environment
    export AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID
    export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
    export VAULT_ADDR=${VAULT_ADDR:-}
    export REDACTED_VAULT_TOKEN=${REDACTED_VAULT_TOKEN:-}
    export GCP_PROJECT_ID=${GCP_PROJECT_ID:-}
    
    # Verify before activation
    if ! cmd_verify; then
        echo ""
        echo "❌ Credential verification failed. Cannot activate."
        return 1
    fi
    
    echo ""
    echo "Running Phase 3B deployment..."
    
    # Run the main deployment script
    if [[ -f "${ROOT_DIR}/scripts/phase3b-credentials-inject-activate.sh" ]]; then
        chmod +x "${ROOT_DIR}/scripts/phase3b-credentials-inject-activate.sh"
        bash "${ROOT_DIR}/scripts/phase3b-credentials-inject-activate.sh"
        
        echo ""
        echo "✅ Phase 3B activation complete"
        audit_credential_access "activate" "all"
    else
        echo "❌ Phase 3B deployment script not found"
        return 1
    fi
}

# Command: help
cmd_help() {
    cat << 'EOF'
Phase 3B: Credential Manager CLI

COMMANDS:
  set-aws
    Set AWS credentials
    Usage: ./scripts/phase3b-credential-manager.sh set-aws --key ID --secret SECRET
  
  set-vault
    Set Vault credentials
    Usage: ./scripts/phase3b-credential-manager.sh set-vault --addr URL --token TOKEN
  
  set-gcp
    Set GCP project
    Usage: ./scripts/phase3b-credential-manager.sh set-gcp --project PROJECT_ID
  
  get-all
    List all stored credentials (masked)
    Usage: ./scripts/phase3b-credential-manager.sh get-all
  
  verify
    Verify all credential layers
    Usage: ./scripts/phase3b-credential-manager.sh verify
  
  activate
    Activate Phase 3B deployment with stored credentials
    Usage: ./scripts/phase3b-credential-manager.sh activate
  
  help
    Show this help message

EXAMPLES:
  # Set AWS credentials
  ./scripts/phase3b-credential-manager.sh set-aws --key REDACTED_AWS_ACCESS_KEY_ID --secret xxxxxx
  
  # Set Vault credentials
  ./scripts/phase3b-credential-manager.sh set-vault \\
    --addr https://vault.example.com:8200 \\
    --token hvs.xxxxx
  
  # Verify all layers
  ./scripts/phase3b-credential-manager.sh verify
  
  # Activate Phase 3B
  ./scripts/phase3b-credential-manager.sh activate

CREDENTIAL STORAGE:
  Credentials stored in: ${CRED_STORE}
  Permissions: 0600 (owner read/write only)
  
AUDIT TRAIL:
  All operations logged to: ${AUDIT_FILE}
EOF
}

# Main dispatch
main() {
    local cmd=${1:-help}
    shift || true
    
    case "$cmd" in
        set-aws) cmd_set_aws "$@" ;;
        set-vault) cmd_set_vault "$@" ;;
        set-gcp) cmd_set_gcp "$@" ;;
        get-all) cmd_get_all "$@" ;;
        verify) cmd_verify "$@" ;;
        activate) cmd_activate "$@" ;;
        help|--help|-h) cmd_help ;;
        *)
            echo "❌ Unknown command: $cmd"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
