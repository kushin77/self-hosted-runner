#!/bin/bash

set -euo pipefail

###############################################################################
# Direct Azure Tenant API Setup - Automated No-Ops
# Bypasses interactive prompts; creates SP, assigns roles, stores credentials
###############################################################################

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_DIR="/home/akushnir/self-hosted-runner/logs/azure-setup"
LOG_FILE="/tmp/azure-setup-direct-${TIMESTAMP//:/-}.log"

mkdir -p "$AUDIT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"; }

audit_write() {
    local event_type="$1" event_data="$2"
    echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"event_type\": \"${event_type}\", \"user\": \"${USER}\", \"host\": \"$(hostname)\", \"data\": ${event_data}}" >> "${AUDIT_DIR}/setup-${TIMESTAMP}.jsonl"
}

# Auto-detect subscription (use default)
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
TENANT_ID=$(az account show --query "tenantId" -o tsv)
TENANT_NAME=$(az account show --query "name" -o tsv)

log "Subscription: $SUBSCRIPTION_ID"
log "Tenant: $TENANT_NAME ($TENANT_ID)"
audit_write "setup_started" "{\"subscription_id\": \"$SUBSCRIPTION_ID\", \"tenant_id\": \"$TENANT_ID\"}"

# Step 1: Create Service Principal
log "Creating service principal..."
sp_name="automation-tenant-api-${TIMESTAMP:0:10}"
sp_output=$(az ad sp create-for-rbac \
    --name "http://$sp_name" \
    --display-name "NexusShield Automation - Tenant Wide API" \
    --role "Owner" \
    --scopes "/subscriptions/$SUBSCRIPTION_ID" \
    --output json)

AZURE_CLIENT_ID=$(echo "$sp_output" | jq -r '.appId')
AZURE_CLIENT_SECRET=$(echo "$sp_output" | jq -r '.password')
AZURE_TENANT_ID=$(echo "$sp_output" | jq -r '.tenant')

success "Service Principal created: $AZURE_CLIENT_ID"
audit_write "sp_created" "{\"client_id\": \"$AZURE_CLIENT_ID\", \"tenant_id\": \"$AZURE_TENANT_ID\"}"

# Step 2: Get SP Object ID and assign additional roles
log "Assigning additional RBAC roles..."
sp_object_id=$(az ad sp show --id "$AZURE_CLIENT_ID" --query "id" -o tsv)

roles=(
    "User Access Administrator"
    "Cognitive Services Contributor"
    "Key Vault Administrator"
    "Secrets Officer"
)

for role in "${roles[@]}"; do
    log "  Assigning: $role"
    az role assignment create \
        --assignee-object-id "$sp_object_id" \
        --assignee-principal-type ServicePrincipal \
        --role "$role" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" 2>/dev/null || true
done

success "RBAC roles assigned"
audit_write "roles_assigned" "{\"count\": ${#roles[@]}}"

# Step 3: Verify SP credentials work
log "Verifying service principal authentication..."
if az login \
    --service-principal \
    -u "$AZURE_CLIENT_ID" \
    -p "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none 2>/dev/null; then
    success "Service principal authentication verified"
    audit_write "sp_verified" '{"status": "success"}'
else
    error "Service principal authentication failed"
    exit 1
fi

# Step 4: Store in GSM
log "Storing credentials in Google Cloud Secret Manager..."
project_id=$(gcloud config get-value project)

secrets=(
    "azure-tenant-id:$AZURE_TENANT_ID"
    "azure-client-id:$AZURE_CLIENT_ID"
    "azure-client-secret:$AZURE_CLIENT_SECRET"
    "azure-subscription-id:$SUBSCRIPTION_ID"
)

for secret_def in "${secrets[@]}"; do
    name="${secret_def%%:*}" value="${secret_def##*:}"
    if gcloud secrets describe "$name" --project="$project_id" &>/dev/null; then
        echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --project="$project_id" >/dev/null 2>&1
    else
        echo -n "$value" | gcloud secrets create "$name" --data-file=- --replication-policy="automatic" --project="$project_id" >/dev/null 2>&1
    fi
    success "Secret stored: $name"
done
audit_write "gsm_storage" "{\"project_id\": \"$project_id\", \"secrets\": ${#secrets[@]}}"

# Step 5: Store in Vault (if configured)
if [ -n "${VAULT_ADDR:-}" ] && command -v vault &>/dev/null; then
    log "Storing in HashiCorp Vault..."
    if vault token lookup &>/dev/null; then
        vault kv put "secret/azure/tenant-api" \
            tenant_id="$AZURE_TENANT_ID" \
            subscription_id="$SUBSCRIPTION_ID" \
            client_id="$AZURE_CLIENT_ID" \
            client_secret="$AZURE_CLIENT_SECRET" \
            created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1
        success "Credentials stored in Vault"
        audit_write "vault_storage" "{\"path\": \"secret/azure/tenant-api\"}"
    else
        log "Not authenticated to Vault, skipping"
    fi
else
    log "Vault not configured, skipping"
fi

# Step 6: Generate config files
log "Generating configuration files..."
cat > /home/akushnir/self-hosted-runner/config/azure-tenant-api.json <<EOF
{
  "metadata": {
    "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "created_by": "${USER:-automation}",
    "method": "direct_automation"
  },
  "azure": {
    "tenant_id": "$AZURE_TENANT_ID",
    "subscription_id": "$SUBSCRIPTION_ID",
    "client_id": "$AZURE_CLIENT_ID"
  },
  "storage": {
    "gsm_project": "$project_id",
    "vault_path": "secret/azure/tenant-api"
  }
}
EOF
success "Configuration saved: config/azure-tenant-api.json"

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Azure Tenant API Setup Complete (Direct Automation)    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Service Principal:${NC}"
echo "  Tenant ID: $AZURE_TENANT_ID"
echo "  Client ID: $AZURE_CLIENT_ID"
echo "  Subscription: $SUBSCRIPTION_ID"
echo ""
echo -e "${BLUE}Stored In:${NC}"
echo "  GSM: $project_id (4 secrets)"
echo "  Vault: secret/azure/tenant-api (optional)"
echo ""
echo -e "${BLUE}Next:${NC}"
echo "  source scripts/azure-credentials.sh && setup_azure_env"
echo "  az resource list"
echo ""

audit_write "setup_completed" '{"status": "success"}'

log "Setup complete. Audit trail: $AUDIT_DIR"
