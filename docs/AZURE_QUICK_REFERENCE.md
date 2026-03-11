# Azure Tenant API - Quick Reference

**Purpose:** Access tenant-wide Azure resources via service principal  
**Status:** ✅ Ready for Interactive Setup  
**Updated:** March 11, 2026

## One-Line Setup

```bash
bash /home/akushnir/self-hosted-runner/scripts/setup-azure-tenant-api.sh
```

## Fetch Credentials (Pick One)

### Option A: Auto-fetch from GSM (Recommended)
```bash
source /home/akushnir/self-hosted-runner/scripts/azure-credentials.sh
setup_azure_env
```

### Option B: Manual from GSM
```bash
export AZURE_CLIENT_ID=$(gcloud secrets versions access latest --secret="azure-client-id")
export AZURE_CLIENT_SECRET=$(gcloud secrets versions access latest --secret="azure-client-secret")
export AZURE_TENANT_ID=$(gcloud secrets versions access latest --secret="azure-tenant-id")
export AZURE_SUBSCRIPTION_ID=$(gcloud secrets versions access latest --secret="azure-subscription-id")
```

### Option C: From Vault
```bash
export VAULT_ADDR="https://vault.example.com:8200"
vault login
vault kv get -format=json secret/azure/tenant-api | \
  jq -r '.data.data | to_entries[] | "export AZURE_\(.key | ascii_upcase)=\(.value)"' | \
  source /dev/stdin
```

## Login to Azure

```bash
az login --service-principal \
  -u "$AZURE_CLIENT_ID" \
  -p "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID"
```

## Common CLI Commands

| Command | Purpose |
|---------|---------|
| `az account show` | Show current account info |
| `az resource list` | List all resources |
| `az group list` | List resource groups |
| `az group create --name RG --location eastus` | Create resource group |
| `az vm list` | List virtual machines |
| `az webapp list` | List app services |
| `az sqldb list` | List SQL databases |
| `az keyvault list` | List key vaults |
| `az role assignment list` | List role assignments |

## Code Examples

### Node.js (TypeScript)
```typescript
import { DefaultAzureCredential } from "@azure/identity";
import { ResourceManagementClient } from "@azure/arm-resources";

const credential = new DefaultAzureCredential();
const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID;

const client = new ResourceManagementClient(credential, subscriptionId);
const resources = await client.resources.list();

for (const resource of resources) {
  console.log(`${resource.name} (${resource.type})`);
}
```

### Python
```python
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
import os

subscription_id = os.getenv("AZURE_SUBSCRIPTION_ID")
credential = DefaultAzureCredential()
client = ResourceManagementClient(credential, subscription_id)

for resource in client.resources.list():
    print(f"{resource.name} ({resource.type})")
```

### Bash/Shell
```bash
source /home/akushnir/self-hosted-runner/scripts/azure-credentials.sh
setup_azure_env

# List resources
az resource list --query "[].{name:name, type:type}"

# Create resource group
az group create --name "my-rg" --location "eastus"

# Deploy template
az deployment group create \
  --name "deploy-$(date +%s)" \
  --resource-group "my-rg" \
  --template-file "./template.json"
```

## Verify Access

```bash
# Simple check
az account show

# Detailed check
az account list-locations | head -5

# List all subscriptions (should show at least one)
az account list --query "[].name"
```

## Storage Locations

| System | Path | Type |
|--------|------|------|
| **GSM** | `azure-{tenant-id,client-id,client-secret,subscription-id}` | Secret Manager |
| **Vault** | `secret/azure/tenant-api` | KV v2 |
| **Local Config** | `config/azure-tenant-api.json` | JSON |
| **Examples** | `docs/AZURE_API_USAGE_EXAMPLES.md` | Markdown |

## Rotation

Every 90 days:
```bash
# Create new credentials
NEW_SECRET=$(az ad app credential reset --id "$AZURE_CLIENT_ID" --query "password" -o tsv)

# Update GSM
echo -n "$NEW_SECRET" | gcloud secrets versions add azure-client-secret --data-file=-

# Update Vault
vault kv put secret/azure/tenant-api client_secret="$NEW_SECRET"
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `not authenticated` | Run `setup_azure_env` or `az login ...` |
| `access denied` | Check IAM permissions on subscription |
| `Command not found: az` | Install: `curl -sL https://aka.ms/InstallAzureCliDeb \| sudo bash` |
| `secret not found` | Verify GSM secret exists: `gcloud secrets list \| grep azure` |
| `vault access denied` | Run `vault login` first |

## Environment Variables

```
AZURE_TENANT_ID        Tenant ID (from setup)
AZURE_CLIENT_ID        Service Principal app ID
AZURE_CLIENT_SECRET    Service Principal password
AZURE_SUBSCRIPTION_ID  Subscription to use
```

## Files

| File | What |
|------|------|
| `scripts/setup-azure-tenant-api.sh` | Interactive setup (start here) |
| `scripts/azure-credentials.sh` | Fetch credentials at runtime |
| `config/azure-tenant-api.json` | Configuration details |
| `docs/AZURE_TENANT_API_SETUP.md` | Full documentation |
| `docs/AZURE_API_USAGE_EXAMPLES.md` | Code examples |

---

**First time?** Run: `bash scripts/setup-azure-tenant-api.sh`  
**Every time (optional):** `source scripts/azure-credentials.sh && setup_azure_env`
