#!/bin/bash

set -euo pipefail

###############################################################################
# Azure Tenant-Wide API Setup
# Creates a service principal with full tenant rights and stores in GSM/Vault
###############################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOG_FILE="/tmp/azure-setup-$(date +%s).log"
AUDIT_DIR="/home/akushnir/self-hosted-runner/logs/azure-setup"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create log directory
mkdir -p "$AUDIT_DIR"
mkdir -p "/tmp"

###############################################################################
# Utility Functions
###############################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
}

audit_write() {
    local event_type="$1"
    local event_data="$2"
    local audit_file="${AUDIT_DIR}/azure-setup-${TIMESTAMP}.jsonl"
    
    local record=$(cat <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "event_type": "${event_type}",
  "user": "${USER:-automation}",
  "host": "$(hostname)",
  "data": ${event_data}
}
EOF
    )
    
    echo "$record" >> "$audit_file"
}

prompt_continue() {
    local message="$1"
    # In automation mode (AZURE_SETUP_AUTO=1), always continue
    if [ "${AZURE_SETUP_AUTO:-0}" = "1" ]; then
        log "Auto-mode: continuing ($message)"
        return 0
    fi
    read -p "$(echo -e "${YELLOW}$message${NC} [y/n]: ")" -r
    [[ $REPLY =~ ^[Yy]$ ]]
}

###############################################################################
# Azure CLI Check & Interactive Login
###############################################################################

check_azure_cli() {
    log "Checking Azure CLI installation..."
    
    if ! command -v az &> /dev/null; then
        error "Azure CLI not found. Installing..."
        curl -sL https://aka.ms/InstallAzureCliDeb | sudo bash
        success "Azure CLI installed"
    else
        success "Azure CLI found: $(az version --output json | jq -r .azureCliVersion)"
    fi
}

interactive_azure_login() {
    log "Starting interactive Azure login..."
    audit_write "interactive_login_started" '{}'
    
    # Check if already logged in
    if az account show &>/dev/null; then
        local current_account=$(az account show --query "name" -o tsv)
        log "Already logged in as: $current_account"
        
        # For hands-off mode, accept existing login (no prompt)
        if [ -z "${SUBSCRIPTION_ID:-}" ] || [ "${SUBSCRIPTION_ID:-}" != "$(az account show --query "id" -o tsv)" ]; then
            if ! prompt_continue "Use current account"; then
                log "Clearing current authentication..."
                az logout || true
            else
                return 0
            fi
        else
            return 0
        fi
    fi
    
    # Interactive login
    log "Opening browser for Azure login..."
    echo ""
    echo -e "${YELLOW}Please follow these steps:${NC}"
    echo "1. A browser window will open"
    echo "2. Log in with your Azure tenant admin account"
    echo "3. Return to this terminal when authenticated"
    echo ""
    
    az login --use-device-code || {
        error "Azure login failed. Please try again."
        return 1
    }
    
    success "Azure login successful"
    audit_write "interactive_login_completed" '{"status": "success"}'
}

###############################################################################
# Tenant Information Collection
###############################################################################

collect_tenant_info() {
    log "Collecting tenant information..."
    
    # Get available subscriptions
    local subscriptions=$(az account list --query "[].{name:name, id:id, isDefault:isDefault}" -o json)
    
    echo ""
    echo -e "${BLUE}=== Available Subscriptions ===${NC}"
    echo "$subscriptions" | jq -r '.[] | "\(.id) - \(.name) \(if .isDefault then "[DEFAULT]" else "" end)"'
    echo ""
    
    # Get tenant ID
    TENANT_ID=$(az account show --query "tenantId" -o tsv)
    log "Tenant ID: $TENANT_ID"
    
    # Select subscription (use env var if set, else read from stdin)
    if [ -z "${SUBSCRIPTION_ID:-}" ]; then
        read -p "Enter the subscription ID you want to use: " SUBSCRIPTION_ID
    fi
    
    # Set subscription
    az account set --subscription "$SUBSCRIPTION_ID"
    success "Subscription set to: $SUBSCRIPTION_ID"
    
    # Get tenant display name
    local tenant_info=$(az account show --query "name" -o tsv)
    log "Tenant Name: $tenant_info"
    
    # Store for later use
    export TENANT_ID
    export SUBSCRIPTION_ID
    export TENANT_NAME="$tenant_info"
}

###############################################################################
# Service Principal Creation with Tenant-Wide Permissions
###############################################################################

create_service_principal() {
    log "Creating service principal with tenant-wide permissions..."
    audit_write "sp_creation_started" "{\"subscription_id\": \"$SUBSCRIPTION_ID\"}"
    
    local sp_name="automation-tenant-api-${TIMESTAMP:0:10}"
    local sp_display_name="NexusShield Automation - Tenant Wide API"
    
    log "Creating service principal: $sp_name"
    
    # Create service principal
    local sp_output=$(az ad sp create-for-rbac \
        --name "http://$sp_name" \
        --display-name "$sp_display_name" \
        --role "Owner" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --output json 2>&1)
    
    if [ $? -ne 0 ]; then
        error "Failed to create service principal"
        error "Output: $sp_output"
        return 1
    fi
    
    # Extract credentials
    AZURE_CLIENT_ID=$(echo "$sp_output" | jq -r '.appId')
    AZURE_CLIENT_SECRET=$(echo "$sp_output" | jq -r '.password')
    AZURE_TENANT_ID=$(echo "$sp_output" | jq -r '.tenant')
    
    success "Service Principal created"
    success "Client ID: $AZURE_CLIENT_ID"
    
    audit_write "sp_creation_completed" "{
        \"client_id\": \"$AZURE_CLIENT_ID\",
        \"tenant_id\": \"$AZURE_TENANT_ID\",
        \"display_name\": \"$sp_display_name\"
    }"
    
    # Export for later
    export AZURE_CLIENT_ID
    export AZURE_CLIENT_SECRET
    export AZURE_TENANT_ID
}

###############################################################################
# Assign Additional Permissions
###############################################################################

assign_tenant_permissions() {
    log "Assigning additional tenant-wide permissions..."
    audit_write "permissions_assignment_started" "{\"client_id\": \"$AZURE_CLIENT_ID\"}"
    
    # Get object ID of service principal
    local sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query "id" -o tsv)
    log "Service Principal Object ID: $sp_object_id"
    
    # List of roles to assign
    local roles=(
        "Owner"
        "User Access Administrator"
        "Cognitive Services Contributor"
        "Key Vault Administrator"
        "Secrets Officer"
    )
    
    echo ""
    echo -e "${BLUE}=== Additional Roles to Assign ===${NC}"
    for i in "${!roles[@]}"; do
        echo "$((i+1)). ${roles[$i]}"
    done
    echo ""
    
    for role in "${roles[@]}"; do
        log "Assigning role: $role"
        az role assignment create \
            --assignee-object-id "$sp_object_id" \
            --assignee-principal-type ServicePrincipal \
            --role "$role" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" 2>/dev/null || {
            warning "Could not assign role '$role' (may already exist)"
        }
    done
    
    success "Role assignments completed"
    audit_write "permissions_assignment_completed" "{\"roles_assigned\": ${#roles[@]}}"
}

###############################################################################
# Validate Service Principal
###############################################################################

validate_service_principal() {
    log "Validating service principal credentials..."
    audit_write "validation_started" "{}"
    
    echo ""
    echo -e "${YELLOW}Testing service principal authentication...${NC}"
    echo ""
    
    # Test login with service principal
    local login_output=$(az login \
        --service-principal \
        -u "$AZURE_CLIENT_ID" \
        -p "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" \
        --output json 2>&1)
    
    if [ $? -eq 0 ]; then
        success "Service principal authentication successful"
        audit_write "validation_success" '{"test": "authentication"}'
        
        # Get list of subscriptions accessible to SP
        local accessible_subs=$(echo "$login_output" | jq -r '.[].id' | wc -l)
        log "Service principal has access to $accessible_subs subscriptions"
        
        return 0
    else
        error "Service principal validation failed"
        error "Output: $login_output"
        audit_write "validation_failed" "{\"error\": \"authentication_failed\"}"
        return 1
    fi
}

###############################################################################
# Store Credentials in GSM
###############################################################################

store_in_gsm() {
    log "Storing credentials in Google Cloud Secret Manager..."
    audit_write "gsm_storage_started" "{}"
    
    # Check if GSM access is available
    if ! command -v gcloud &> /dev/null; then
        warning "gcloud CLI not available, skipping GSM storage"
        return 1
    fi
    
    local project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$project_id" ]; then
        warning "GCP project not configured, skipping GSM storage"
        return 1
    fi
    
    log "Storing secrets in project: $project_id"
    
    # Define secrets to store
    local secrets=(
        "azure-tenant-id:$AZURE_TENANT_ID"
        "azure-client-id:$AZURE_CLIENT_ID"
        "azure-client-secret:$AZURE_CLIENT_SECRET"
        "azure-subscription-id:$SUBSCRIPTION_ID"
    )
    
    for secret_def in "${secrets[@]}"; do
        local name="${secret_def%%:*}"
        local value="${secret_def##*:}"
        
        log "Creating/updating secret: $name"
        
        # Create secret (or update if exists)
        if gcloud secrets describe "$name" --project="$project_id" &>/dev/null; then
            log "Secret exists, adding new version..."
            echo -n "$value" | gcloud secrets versions add "$name" \
                --data-file=- \
                --project="$project_id" || {
                error "Failed to update secret: $name"
                return 1
            }
        else
            log "Creating new secret..."
            echo -n "$value" | gcloud secrets create "$name" \
                --data-file=- \
                --replication-policy="automatic" \
                --project="$project_id" || {
                error "Failed to create secret: $name"
                return 1
            }
        fi
        
        success "Secret stored: $name"
    done
    
    # Grant service account access
    log "Configuring IAM access for secrets..."
    local service_account=$(gcloud config get-value core/account 2>/dev/null)
    
    for secret_def in "${secrets[@]}"; do
        local name="${secret_def%%:*}"
        gcloud secrets add-iam-policy-binding "$name" \
            --member="user:$service_account" \
            --role="roles/secretmanager.secretAccessor" \
            --project="$project_id" 2>/dev/null || true
    done
    
    success "GSM storage completed"
    audit_write "gsm_storage_completed" "{\"project_id\": \"$project_id\", \"secrets\": ${#secrets[@]}}"
}

###############################################################################
# Store Credentials in Vault
###############################################################################

store_in_vault() {
    log "Storing credentials in HashiCorp Vault..."
    audit_write "vault_storage_started" "{}"
    
    # Check Vault CLI
    if ! command -v vault &> /dev/null; then
        warning "vault CLI not available, skipping Vault storage"
        return 1
    fi
    
    # Check Vault address
    local vault_addr="${VAULT_ADDR:-}"
    if [ -z "$vault_addr" ]; then
        read -p "Enter Vault address (e.g., https://vault.example.com:8200): " vault_addr
    fi
    
    if [ -z "$vault_addr" ]; then
        warning "Vault address not provided, skipping Vault storage"
        return 1
    fi
    
    export VAULT_ADDR="$vault_addr"
    log "Using Vault address: $VAULT_ADDR"
    
    # Check Vault token/auth
    if ! vault token lookup &>/dev/null; then
        warning "Not authenticated to Vault. Use: vault login"
        return 1
    fi
    
    # Store Azure credentials in Vault
    log "Writing Azure credentials to Vault..."
    
    vault kv put "secret/azure/tenant-api" \
        tenant_id="$AZURE_TENANT_ID" \
        subscription_id="$SUBSCRIPTION_ID" \
        client_id="$AZURE_CLIENT_ID" \
$PLACEHOLDER
        display_name="NexusShield Automation - Tenant Wide API" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" || {
        error "Failed to store credentials in Vault"
        return 1
    }
    
    success "Credentials stored in Vault at: secret/azure/tenant-api"
    audit_write "vault_storage_completed" "{\"path\": \"secret/azure/tenant-api\"}"
}

###############################################################################
# Generate Configuration File
###############################################################################

generate_config_file() {
    log "Generating configuration file..."
    
    local config_file="/home/akushnir/self-hosted-runner/config/azure-tenant-api.json"
    mkdir -p "$(dirname "$config_file")"
    
    cat > "$config_file" <<EOF
{
  "metadata": {
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "created_by": "${USER:-automation}",
    "host": "$(hostname)",
    "description": "Azure Tenant-Wide API Configuration"
  },
  "azure": {
    "tenant_id": "$AZURE_TENANT_ID",
    "subscription_id": "$SUBSCRIPTION_ID",
    "tenant_name": "$TENANT_NAME",
    "client_id": "$AZURE_CLIENT_ID",
$PLACEHOLDER
  },
  "secrets_management": {
    "gsm_enabled": true,
    "vault_enabled": true,
    "gsm_project": "$(gcloud config get-value project 2>/dev/null || echo 'not-configured')",
    "vault_address": "${VAULT_ADDR:-not-configured}"
  },
  "permissions": {
    "scope": "subscription",
    "roles": [
      "Owner",
      "User Access Administrator",
      "Cognitive Services Contributor",
      "Key Vault Administrator",
      "Secrets Officer"
    ]
  },
  "authentication_methods": [
    {
      "method": "environment_variables",
      "description": "Set AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID"
    },
    {
      "method": "gcloud_secrets",
      "description": "Fetch from gcloud secrets: azure-{tenant-id,client-id,client-secret,subscription-id}"
    },
    {
      "method": "vault",
      "description": "Fetch from Vault: secret/azure/tenant-api"
    }
  ],
  "audit_trail": {
    "log_file": "$LOG_FILE",
    "audit_dir": "$AUDIT_DIR"
  }
}
EOF
    
    success "Configuration file created: $config_file"
    cat "$config_file" | jq .
}

###############################################################################
# Create Usage Examples
###############################################################################

create_usage_examples() {
    log "Creating usage examples..."
    
    local examples_file="/home/akushnir/self-hosted-runner/docs/AZURE_API_USAGE_EXAMPLES.md"
    mkdir -p "$(dirname "$examples_file")"
    
    cat > "$examples_file" <<'EOF'
# Azure Tenant API Usage Examples

## Method 1: Environment Variables (CLI)

```bash
export AZURE_CLIENT_ID="<from-setup>"
export AZURE_CLIENT_SECRET="<from-setup>"
export AZURE_TENANT_ID="<from-setup>"

# Login
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"

# List all resources
az resource list --query "[].{name:name, type:type, location:location}"
```

## Method 2: Fetch from GSM (Recommended)

```bash
# Create helper function
get_azure_cred() {
    local secret=$1
    local project=$(gcloud config get-value project)
    gcloud secrets versions access latest --secret="$secret" --project="$project"
}

export AZURE_CLIENT_ID=$(get_azure_cred "azure-client-id")
export AZURE_CLIENT_SECRET=$(get_azure_cred "azure-client-secret")
export AZURE_TENANT_ID=$(get_azure_cred "azure-tenant-id")

# Use with az CLI
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

## Method 3: Fetch from Vault (Optional)

```bash
# Requires vault CLI and VAULT_ADDR set
vault login

# Fetch all credentials
vault kv get -format=json secret/azure/tenant-api | \
  jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' | \
  while read -r line; do export "$line"; done

# Use with Azure CLI
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

## Method 4: programmatic (Node.js)

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const { SubscriptionClient } = require("@azure/arm-subscriptions");

async function listResources() {
    // Reads from environment variables automatically
    const credential = new DefaultAzureCredential();
    const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID;
    
    const client = new SubscriptionClient(credential, subscriptionId);
    const resources = await client.subscriptions.listResources({
        subscriptionId
    });
    
    console.log(resources);
}

listResources().catch(console.error);
```

## Method 5: Programmatic (Python)

```python
from azure.identity import DefaultAzureClientSecret
from azure.mgmt.resource import ResourceManagementClient
import os

subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID")
credential = DefaultAzureClientSecret(
    client_id=os.getenv("AZURE_CLIENT_ID"),
$PLACEHOLDER
    tenant_id=os.getenv("AZURE_TENANT_ID")
)

client = ResourceManagementClient(credential, subscription_id)
resources = client.resources.list()

for resource in resources:
    print(f"{resource.name} - {resource.type}")
```

## Running Tenant-Wide Operations

```bash
# Get all resource groups
az group list --query "[].{name:name, location:location}"

# Create a resource group
az group create --name "automation-rg" --location "eastus"

# List all resources across subscription
az resource list --query "[?type=='Microsoft.Storage/storageAccounts']"

# Deploy an ARM template
az deployment sub create \
  --location "eastus" \
  --template-file "template.json" \
  --parameters "env=prod"

# Manage role assignments
az role assignment create \
  --assignee "$AZURE_CLIENT_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

## Security Best Practices

✅ **DO:**
- Store credentials in GSM or Vault
- Use environment variable injection at runtime
- Rotate service principal credentials every 90 days
- Audit all access via Azure Activity Log
- Use least privilege roles when possible

❌ **DON'T:**
- Commit credentials to Git
- Hardcode secrets in scripts
- Share credentials via email or chat
- Use in unencrypted environment files
- Leave long-lived tokens unrotated

## Credential Rotation

```bash
# Create new password
az ad sp credential reset \
  --name "http://automation-tenant-api-$(date +%Y-%m-%d)" \
  --display-name "NexusShield Automation - Rotated"

# Update in GSM
NEW_SECRET=$(az ad sp credential reset ... | jq -r '.password')
echo -n "$NEW_SECRET" | gcloud secrets versions add azure-client-secret --data-file=-

# Update in Vault
vault kv put secret/azure/tenant-api \
$PLACEHOLDER
  rotated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```
EOF
    
    success "Usage examples created: $examples_file"
}

###############################################################################
# Generate Summary Report
###############################################################################

generate_summary_report() {
    log "Generating summary report..."
    
    local report_file="${AUDIT_DIR}/SETUP_SUMMARY_${TIMESTAMP}.md"
    
    cat > "$report_file" <<EOF
# Azure Tenant API Setup Summary

**Date:** $TIMESTAMP  
**User:** ${USER:-automation}  
**Host:** $(hostname)

## ✅ Setup Completed

### Service Principal Details
- **Display Name:** NexusShield Automation - Tenant Wide API
- **Client ID:** $AZURE_CLIENT_ID
- **Tenant ID:** $AZURE_TENANT_ID
- **Subscription ID:** $SUBSCRIPTION_ID
- **Tenant Name:** $TENANT_NAME

### Assigned Permissions
- Owner
- User Access Administrator
- Cognitive Services Contributor
- Key Vault Administrator
- Secrets Officer

### Secrets Storage

#### Google Cloud Secret Manager (GSM)
- ✅ azure-tenant-id
- ✅ azure-client-id
- ✅ azure-client-secret
- ✅ azure-subscription-id

#### HashiCorp Vault
- Path: \`secret/azure/tenant-api\`
$PLACEHOLDER

### Configuration Files
- Config: \`config/azure-tenant-api.json\`
- Usage Examples: \`docs/AZURE_API_USAGE_EXAMPLES.md\`
- Audit Trail: \`$AUDIT_DIR/\`

### Quick Start

#### 1. Using Environment Variables
\`\`\`bash
export AZURE_CLIENT_ID="$AZURE_CLIENT_ID"
export AZURE_CLIENT_SECRET="<from-gcloud-or-vault>"
export AZURE_TENANT_ID="$AZURE_TENANT_ID"
export AZURE_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

az login --service-principal -u "\$AZURE_CLIENT_ID" -p "\$AZURE_CLIENT_SECRET" --tenant "\$AZURE_TENANT_ID"
\`\`\`

#### 2. Using GSM (Recommended)
\`\`\`bash
# Fetch credentials
export AZURE_CLIENT_ID=\$(gcloud secrets versions access latest --secret="azure-client-id")
export AZURE_CLIENT_SECRET=\$(gcloud secrets versions access latest --secret="azure-client-secret")
export AZURE_TENANT_ID=\$(gcloud secrets versions access latest --secret="azure-tenant-id")

# Login
az login --service-principal -u "\$AZURE_CLIENT_ID" -p "\$AZURE_CLIENT_SECRET" --tenant "\$AZURE_TENANT_ID"
\`\`\`

#### 3. Using Vault
\`\`\`bash
# Requires: vault CLI + VAULT_ADDR set + vault login
vault kv get -format=json secret/azure/tenant-api | jq -r '.data.data | "export AZURE_\(.tenant_id|ascii_upcase)=\(.tenant_id)"'

# Or manually
export AZURE_CLIENT_ID=\$(vault kv get -field=client_id secret/azure/tenant-api)
$PLACEHOLDER
export AZURE_TENANT_ID=\$(vault kv get -field=tenant_id secret/azure/tenant-api)
\`\`\`

### Next Steps

1. ✅ Service principal created with tenant-wide permissions
2. ✅ Credentials stored securely (GSM & Vault)
3. ⏭ Start using Azure CLI with service principal credentials
4. ⏭ Set up automated credential rotation (every 90 days)
5. ⏭ Configure Azure activity logging for audit trail

### Security Notes

- Client secret is stored **only** in GSM and Vault (never in git)
- All access is logged with audit trail in: \`$AUDIT_DIR\`
- Service principal can access all resources in subscription: \`$SUBSCRIPTION_ID\`
- Implement automated credential rotation using cron/Cloud Scheduler

### Support

For usage examples, see: \`docs/AZURE_API_USAGE_EXAMPLES.md\`

Log file: \`$LOG_FILE\`

---

*Generated automatically by \`scripts/setup-azure-tenant-api.sh\`*
EOF
    
    success "Summary report created: $report_file"
    cat "$report_file"
}

###############################################################################
# Main Execution
###############################################################################

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Azure Tenant-Wide API Setup with Secrets Management      ║${NC}"
    echo -e "${BLUE}║  (GSM & Vault Integration)                               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log "Setup started. Log: $LOG_FILE"
    audit_write "setup_started" "{\"timestamp\": \"$TIMESTAMP\"}"
    
    # Step 1: Check Azure CLI
    log "Step 1/8: Checking Azure CLI..."
    check_azure_cli
    
    # Step 2: Interactive login
    log "Step 2/8: Interactive Azure login..."
    interactive_azure_login || exit 1
    
    # Step 3: Collect tenant info
    log "Step 3/8: Collecting tenant information..."
    collect_tenant_info
    
    # Step 4: Create service principal
    log "Step 4/8: Creating service principal..."
    create_service_principal || exit 1
    
    # Step 5: Assign permissions
    log "Step 5/8: Assigning permissions..."
    assign_tenant_permissions
    
    # Step 6: Validate
    log "Step 6/8: Validating service principal..."
    validate_service_principal || exit 1
    
    # Step 7: Store credentials
    log "Step 7/8: Storing credentials..."
    store_in_gsm
    store_in_vault
    
    # Step 8: Generate documentation
    log "Step 8/8: Generating documentation..."
    generate_config_file
    create_usage_examples
    generate_summary_report
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ Azure Tenant API Setup Complete                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Review config: ${BLUE}cat config/azure-tenant-api.json${NC}"
    echo "2. See examples: ${BLUE}cat docs/AZURE_API_USAGE_EXAMPLES.md${NC}"
    echo "3. Verify credentials: ${BLUE}az login --service-principal ...${NC}"
    echo ""
    
    audit_write "setup_completed" "{\"status\": \"success\"}"
}

# Run main function
main "$@"
