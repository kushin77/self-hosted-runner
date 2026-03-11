# Azure Tenant-Wide API Setup Guide

**Date:** March 11, 2026  
**Status:** Complete & Ready for Interactive Setup  
**Integration:** GSM, Vault, and Azure Portal

## Overview

This guide provides **interactive setup** for a tenant-wide Azure service principal with full permissions, integrated into your secrets management system (Google Cloud Secret Manager & HashiCorp Vault).

## What You'll Get

✅ **Tenant-Wide Access:** Service principal with `Owner` role on subscription  
✅ **Multi-Cloud Storage:** Credentials in both GSM and Vault  
✅ **Zero Hardcoding:** All secrets managed externally  
✅ **Audit Trail:** Complete immutable log of all operations  
✅ **Runtime Injection:** Automatic credential fetching at execution time  

## Prerequisites

```bash
# Required
- Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli
- Active Azure subscription with admin/owner access
- gcloud CLI has google-cloud-secret-manager API enabled
- (Optional) HashiCorp Vault access

# Check prerequisites
az --version
gcloud --version
vault --version 2>/dev/null || echo "Vault not installed (optional)"
```

## Quick Start

### Option 1: Full Interactive Setup (Recommended)

```bash
# Run the interactive setup script
bash /home/akushnir/self-hosted-runner/scripts/setup-azure-tenant-api.sh
```

**What happens:**
1. Azure CLI checks & installation (if needed)
2. Opens browser for interactive Azure login
3. Collects tenant and subscription information
4. Creates service principal with tenant-wide permissions
5. Assigns multiple RBAC roles
6. Validates credentials work
7. Stores in GSM automatically
8. Stores in Vault (if configured)
9. Generates configuration files & examples

**Expected output:**
```
✓ Azure CLI found: 2.54.0
✓ Azure login successful
✓ Subscription set to: <sub-id>
✓ Service Principal created
✓ Client ID: <client-id>
✓ Credentials stored in GSM
✓ Vault storage completed
✓ Configuration file created
✓ Usage examples created
✓ Summary report created
```

### Option 2: Manual Setup (if script fails)

If you prefer to skip the script, here are the manual steps:

#### Step 1: Interactive Login

```bash
az login --use-device-code
```

Follow the browser prompt to authenticate with your Azure account.

#### Step 2: Select Subscription

```bash
# List all subscriptions
az account list --query "[].{id:id, name:name, isDefault:isDefault}"

# Set the one you want
az account set --subscription "<subscription-id>"
```

#### Step 3: Create Service Principal

```bash
# Create with subscription-level Owner access
az ad sp create-for-rbac \
  --name "http://automation-tenant-api-$(date +%Y-%m-%d)" \
  --display-name "NexusShield Automation - Tenant Wide API" \
  --role "Owner" \
  --scopes "/subscriptions/<subscription-id>"
```

**Save the output** - contains: `appId`, `password`, `tenant`

#### Step 4: Get Service Principal Object ID

```bash
# Replace with your appId from previous step
OBJECT_ID=$(az ad sp show --id "<appId>" --query "id" -o tsv)
echo "Object ID: $OBJECT_ID"
```

#### Step 5: Assign Additional Roles

```bash
# For tenant-wide capabilities
az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/<subscription-id>"

az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Cognitive Services Contributor" \
  --scope "/subscriptions/<subscription-id>"

az role assignment create \
  --assignee-object-id "$OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Administrator" \
  --scope "/subscriptions/<subscription-id>"
```

#### Step 6: Store in GSM

```bash
PROJECT_ID=$(gcloud config get-value project)

# Store each credential
echo -n "<appId>" | gcloud secrets create azure-client-id \
  --data-file=- --replication-policy="automatic" \
  --project="$PROJECT_ID"

echo -n "<password>" | gcloud secrets create azure-client-secret \
  --data-file=- --replication-policy="automatic" \
  --project="$PROJECT_ID"

echo -n "<tenant>" | gcloud secrets create azure-tenant-id \
  --data-file=- --replication-policy="automatic" \
  --project="$PROJECT_ID"

echo -n "<subscription-id>" | gcloud secrets create azure-subscription-id \
  --data-file=- --replication-policy="automatic" \
  --project="$PROJECT_ID"
```

#### Step 7: Store in Vault (Optional)

```bash
export VAULT_ADDR="https://vault.example.com:8200"
vault login

vault kv put secret/azure/tenant-api \
  tenant_id="<tenant>" \
  subscription_id="<subscription-id>" \
  client_id="<appId>" \
$PLACEHOLDER
```

## Using Azure Credentials

### Method 1: Fetch from GSM (Recommended)

```bash
# Source the credential helper
source /home/akushnir/self-hosted-runner/scripts/azure-credentials.sh

# Set up environment
setup_azure_env

# Verify access
verify_azure_access

# Now use Azure CLI
az resource list --query "[].{name:name, type:type}"
```

### Method 2: Manual Environment Variables

```bash
export AZURE_CLIENT_ID=$(gcloud secrets versions access latest --secret="azure-client-id")
export AZURE_CLIENT_SECRET=$(gcloud secrets versions access latest --secret="azure-client-secret")
export AZURE_TENANT_ID=$(gcloud secrets versions access latest --secret="azure-tenant-id")
export AZURE_SUBSCRIPTION_ID=$(gcloud secrets versions access latest --secret="azure-subscription-id")

# Login
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"

# Verify
az account show
```

### Method 3: Use Vault

```bash
export VAULT_ADDR="https://vault.example.com:8200"
vault login

# Get all credentials
vault kv get -format=json secret/azure/tenant-api | \
  jq -r '.data.data | to_entries[] | "export AZURE_\(.key | ascii_upcase)=\(.value)"' | \
  source /dev/stdin

# Use directly
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

## Common Operations

### List All Resources

```bash
az resource list \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --query "[].{name:name, type:type, location:location}"
```

### Create a Resource Group

```bash
az group create \
  --name "automation-rg-$(date +%Y%m%d)" \
  --location "eastus"
```

### Deploy ARM Template

```bash
az deployment sub create \
  --name "automation-deploy-$(date +%s)" \
  --location "eastus" \
  --template-file "template.json" \
  --parameters "env=prod"
```

### Manage Managed Identities

```bash
# Create a managed identity
az identity create \
  --resource-group "automation-rg" \
  --name "automation-identity"

# Get details
az identity show \
  --resource-group "automation-rg" \
  --name "automation-identity"
```

### Assign Azure Roles

```bash
# Find the principal ID
PRINCIPAL_ID=$(azure identity show \
  --resource-group "automation-rg" \
  --name "automation-identity" \
  --query "principalId" -o tsv)

# Assign role
az role assignment create \
  --assignee-object-id "$PRINCIPAL_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

### Query with Power

```bash
# Find all storage accounts in subscription
az storage account list \
  --resource-group "automation-rg" \
  --query "[].{name:name, tier:sku.tier, kind:kind}"

# Find all Key Vaults
az keyvault list \
  --resource-group "automation-rg" \
  --query "[].{name:name, location:location}"

# Find all VMs and their states
az vm list \
  --resource-group "automation-rg" \
  --query "[].{name:name, osProfile:{computerName:osProfile.computerName}, powerState:powerState}"
```

## File Locations

| File | Purpose |
|------|---------|
| `scripts/setup-azure-tenant-api.sh` | Main interactive setup script |
| `scripts/azure-credentials.sh` | Credential fetcher & environment setup |
| `config/azure-tenant-api.json` | Service principal configuration |
| `docs/AZURE_API_USAGE_EXAMPLES.md` | Code examples (Node.js, Python, CLI) |
| `logs/azure-setup/` | Audit trail & setup logs |

## Secrets Storage

### Google Cloud Secret Manager (GSM)

```
azure-client-id
azure-client-secret
azure-tenant-id
azure-subscription-id
```

**Fetch one:**
```bash
gcloud secrets versions access latest --secret="azure-client-id" --project="$(gcloud config get-value project)"
```

### HashiCorp Vault

```
Path: secret/azure/tenant-api
$PLACEHOLDER
```

**Fetch one:**
```bash
vault kv get -field="client_id" secret/azure/tenant-api
```

## Security Best Practices

### ✅ DO:
- Store secrets in **GSM only** (never in git)
- Fetch credentials at runtime from GSM/Vault
- Use service principal for automation (never personal accounts)
- Rotate service principal credentials every 90 days
- Audit all Azure access via Activity Log
- Restrict role assignments to least privilege
- Use separate service principals per environment

### ❌ DON'T:
- Commit client secret to Git
- Hardcode credentials in scripts
- Share credentials via email/chat/Slack
- Use in unencrypted `.env` files
- Leave credentials in shell history
- Use interactive personal login for automation
- Create permanent credentials without rotation policy

## Credential Rotation (Every 90 Days)

```bash
#!/bin/bash

# Create new credentials
NEW_CRED=$(az ad app credential reset \
  --id "<appId>" \
  --display-name "Rotated $(date +%Y-%m-%d)" \
  --query "password" -o tsv)

# Update in GSM
echo -n "$NEW_CRED" | gcloud secrets versions add azure-client-secret \
  --data-file=- \
  --project="$(gcloud config get-value project)"

# Update in Vault (if applicable)
vault kv put secret/azure/tenant-api \
$PLACEHOLDER
  rotated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Audit
echo "Credential rotated: $(date)" >> /var/log/azure-rotation.log
```

## Troubleshooting

### Azure CLI not found

```bash
# Install on Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCliDeb | sudo bash

# Install on macOS
brew install azure-cli

# Verify
az --version
```

### Service Principal Can't Authenticate

```bash
# Verify credentials are correct
echo "Client ID: $AZURE_CLIENT_ID"
echo "Tenant ID: $AZURE_TENANT_ID"
# (Don't echo secret!)

# Try login with detailed output
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  --verbose

# Check if credentials need rotation (90+ days old)
az ad sp show --id "$AZURE_CLIENT_ID" \
  --query "passwordCredentials[]"
```

### GSM Access Denied

```bash
# Verify project is set
gcloud config get-value project

# Verify you're authenticated
gcloud auth list

# Verify secret exists and you have access
gcloud secrets list --filter="name:azure-*"

# Check IAM permissions on secret
gcloud secrets get-iam-policy azure-client-id
```

### Vault Connection Refused

```bash
# Verify VAULT_ADDR is correct
echo $VAULT_ADDR

# Test connectivity
curl -k "$VAULT_ADDR/v1/sys/health"

# Login to Vault
vault login -method=approle \
  role_id="$(vault kv get -field=role_id secret/vault-approle)" \
  secret_id="$(vault kv get -field=secret_id secret/vault-approle)"
```

## Complete Example: Automation Script

```bash
#!/bin/bash

set -euo pipefail

# Setup credentials
source /home/akushnir/self-hosted-runner/scripts/azure-credentials.sh
setup_azure_env

# Verify access
verify_azure_access

# Run automation
echo "Listing all resources in subscription: $AZURE_SUBSCRIPTION_ID"
az resource list --query "[].{name:name, type:type, location:location}" -o table

echo ""
echo "Creating new resource group..."
az group create \
  --name "automation-rg-$(date +%Y%m%d-%H%M%S)" \
  --location "eastus"

echo ""
echo "All done!"
```

## Next Steps

1. ✅ Run the setup script: `bash scripts/setup-azure-tenant-api.sh`
2. ✅ Verify credentials: `source scripts/azure-credentials.sh && verify_azure_access`
3. ✅ Review configuration: `cat config/azure-tenant-api.json | jq`
4. ⏭ Start using Azure API in your automation
5. ⏭ Set up 90-day credential rotation
6. ⏭ Configure Azure Activity Log monitoring

## Support & Audit

- **Execution Log:** Check `/tmp/azure-setup-*.log`
- **Audit Trail:** Check `logs/azure-setup/`
- **Config File:** `config/azure-tenant-api.json`
- **Examples:** `docs/AZURE_API_USAGE_EXAMPLES.md`

---

**Ready to begin?** Run: `bash scripts/setup-azure-tenant-api.sh`
