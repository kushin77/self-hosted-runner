# Deploying Runners on Microsoft Azure

## Overview

This guide deploys self-provisioning runners on Azure VMs using custom script extensions. Runners auto-register with GitHub and self-heal automatically.

## Prerequisites

- Azure subscription with VM creation permissions
- Azure CLI installed and authenticated
- GitHub Personal Access Token (PAT) with `admin:self_hosted_runner` scope
- Resource group created

## Step 1: Create Resource Group

```bash
#!/usr/bin/env bash
# create-rg.sh

RESOURCE_GROUP="github-runners-rg"
LOCATION="eastus"

az group create \
  --name=${RESOURCE_GROUP} \
  --location=${LOCATION}

echo "✓ Resource group created: ${RESOURCE_GROUP}"
```

## Step 2: Store Token in Key Vault

```bash
#!/usr/bin/env bash
# store-token.sh

VAULT_NAME="github-runner-vault-${RANDOM}"
RESOURCE_GROUP="github-runners-rg"
LOCATION="eastus"
GITHUB_TOKEN="ghr_xxxxxxxxxxxxxxxx"

# Create Key Vault
az keyvault create \
  --resource-group=${RESOURCE_GROUP} \
  --name=${VAULT_NAME} \
  --location=${LOCATION} \
  --enabled-for-template-deployment true

# Store token
az keyvault secret set \
  --vault-name=${VAULT_NAME} \
  --name "github-runner-token" \
  --value="${GITHUB_TOKEN}"

echo "✓ Token stored in Key Vault: ${VAULT_NAME}"
```

## Step 3: Create Custom Script Extension

Create `bootstrap-script.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script runs as root
RUNNER_ORG="YOUR_ORG"
RUNNER_URL="https://github.com/${RUNNER_ORG}"
RUNNER_LABELS="azure,vm,linux,docker"
RUNNER_TOKEN="${GITHUB_TOKEN}"  # Passed from ARM template

# Clone and bootstrap
git clone "https://github.com/${RUNNER_ORG}/self-hosted-runner" /opt/runner-platform
cd /opt/runner-platform/bootstrap

export RUNNER_TOKEN
export RUNNER_URL
export RUNNER_LABELS
export RUNNER_HOME="/opt/actions-runner"

bash bootstrap.sh

# Setup monitoring
bash setup-daemons.sh

echo "✓ Runner bootstrap complete"
```

## Step 4: Create ARM Template

Create `runner-template.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vmName": {
      "type": "string",
      "defaultValue": "github-runner"
    },
    "vmSize": {
      "type": "string",
      "defaultValue": "Standard_D2s_v3"
    },
    "vmCount": {
      "type": "int",
      "defaultValue": 3
    },
    "githubToken": {
      "type": "securestring"
    },
    "keyVaultName": {
      "type": "string"
    }
  },
  "variables": {
    "networkInterfaceName": "[concat(parameters('vmName'), '-nic')]",
    "publicIpName": "[concat(parameters('vmName'), '-ip')]",
    "nsgName": "[concat(parameters('vmName'), '-nsg')]",
    "vnetName": "github-runners-vnet",
    "subnetName": "runners-subnet"
  },
  "resources": [
    {
      "type": "Microsoft.Network/virtualNetworks",
      "apiVersion": "2021-02-01",
      "name": "[variables('vnetName')]",
      "location": "[resourceGroup().location]",
      "properties": {
        "addressSpace": {
          "addressPrefixes": ["10.0.0.0/16"]
        },
        "subnets": [
          {
            "name": "[variables('subnetName')]",
            "properties": {
              "addressPrefix": "10.0.0.0/24",
              "networkSecurityGroup": {
                "id": "[resourceId('Microsoft.Network/networkSecurityGroups', variables('nsgName'))]"
              }
            }
          }
        ]
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkSecurityGroups', variables('nsgName'))]"
      ]
    },
    {
      "type": "Microsoft.Network/networkSecurityGroups",
      "apiVersion": "2021-02-01",
      "name": "[variables('nsgName')]",
      "location": "[resourceGroup().location]",
      "properties": {
        "securityRules": [
          {
            "name": "AllowOutboundHTTPS",
            "properties": {
              "description": "Allow HTTPS to GitHub",
              "protocol": "Tcp",
              "sourcePortRange": "*",
              "destinationPortRange": "443",
              "sourceAddressPrefix": "*",
              "destinationAddressPrefix": "Internet",
              "access": "Allow",
              "priority": 100,
              "direction": "Outbound"
            }
          },
          {
            "name": "DenyAllOutbound",
            "properties": {
              "description": "Deny all other outbound",
              "protocol": "*",
              "sourcePortRange": "*",
              "destinationPortRange": "*",
              "sourceAddressPrefix": "*",
              "destinationAddressPrefix": "*",
              "access": "Deny",
              "priority": 1000,
              "direction": "Outbound"
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2021-03-01",
      "name": "[concat(parameters('vmName'), '-', copyIndex())]",
      "location": "[resourceGroup().location]",
      "copy": {
        "name": "vmCopy",
        "count": "[parameters('vmCount')]"
      },
      "properties": {
        "hardwareProfile": {
          "vmSize": "[parameters('vmSize')]"
        },
        "osProfile": {
          "computerName": "[concat(parameters('vmName'), '-', copyIndex())]",
          "adminUsername": "azureuser",
          "linuxConfiguration": {
            "disablePasswordAuthentication": true,
            "ssh": {
              "publicKeys": [
                {
                  "path": "/home/azureuser/.ssh/authorized_keys",
                  "keyData": "ssh-rsa AAAAB3..."
                }
              ]
            }
          }
        },
        "storageProfile": {
          "imageReference": {
            "publisher": "Canonical",
            "offer": "UbuntuServer",
            "sku": "18_04-lts-gen2",
            "version": "latest"
          },
          "osDisk": {
            "createOption": "FromImage",
            "managedDisk": {
              "storageAccountType": "Standard_LRS"
            }
          }
        },
        "networkProfile": {
          "networkInterfaces": [
            {
              "id": "[resourceId('Microsoft.Network/networkInterfaces', concat(variables('networkInterfaceName'), '-', copyIndex()))]"
            }
          ]
        },
        "diagnosticsProfile": {
          "bootDiagnostics": {
            "enabled": true
          }
        }
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkInterfaces', concat(variables('networkInterfaceName'), '-', copyIndex()))]"
      ]
    },
    {
      "type": "Microsoft.Compute/virtualMachines/extensions",
      "apiVersion": "2021-03-01",
      "name": "[concat(parameters('vmName'), '-', copyIndex(), '/CustomScriptExtension')]",
      "location": "[resourceGroup().location]",
      "copy": {
        "name": "extensionCopy",
        "count": "[parameters('vmCount')]"
      },
      "properties": {
        "publisher": "Microsoft.Azure.Extensions",
        "type": "CustomScript",
        "typeHandlerVersion": "2.1",
        "autoUpgradeMinorVersion": true,
        "protectedSettings": {
          "commandToExecute": "[concat('GITHUB_TOKEN=''', parameters('githubToken'), ''' bash bootstrap-script.sh')]",
          "fileUris": [
            "https://YOUR_STORAGE_ACCOUNT.blob.core.windows.net/scripts/bootstrap-script.sh"
          ]
        }
      },
      "dependsOn": [
        "[resourceId('Microsoft.Compute/virtualMachines', concat(parameters('vmName'), '-', copyIndex()))]"
      ]
    }
  ]
}
```

## Step 5: Deploy with Azure CLI

```bash
#!/usr/bin/env bash
# deploy.sh

RESOURCE_GROUP="github-runners-rg"
TEMPLATE_FILE="runner-template.json"
GITHUB_TOKEN="ghr_xxxxxxxxxxxxxxxx"
VAULT_NAME="github-runner-vault-xxxxx"

az deployment group create \
  --resource-group=${RESOURCE_GROUP} \
  --template-file=${TEMPLATE_FILE} \
  --parameters \
    vmName=github-runner \
    vmSize=Standard_D2s_v3 \
    vmCount=3 \
    githubToken=${GITHUB_TOKEN} \
    keyVaultName=${VAULT_NAME}

echo "✓ Deployment complete"
```

## Step 6: Configure Auto Scaling

```bash
#!/usr/bin/env bash
# setup-autoscale.sh

RESOURCE_GROUP="github-runners-rg"
VMSS_NAME="github-runners-vmss"

# Create Virtual Machine Scale Set
az vmss create \
  --resource-group=${RESOURCE_GROUP} \
  --name=${VMSS_NAME} \
  --image UbuntuLTS \
  --vm-sku Standard_D2s_v3 \
  --instance-count=1 \
  --custom-data bootstrap-script.sh

# Create autoscale settings
az monitor autoscale create \
  --resource-group=${RESOURCE_GROUP} \
  --resource=${VMSS_NAME} \
  --resource-type "Microsoft.Compute/virtualMachineScaleSets" \
  --name github-runners-autoscale \
  --min-count=1 \
  --max-count=10 \
  --count=3

echo "✓ Auto scaling configured"
```

## Step 7: Monitor with Azure Monitor

```bash
#!/usr/bin/env bash
# setup-monitoring.sh

RESOURCE_GROUP="github-runners-rg"
WORKSPACE_NAME="github-runners-workspace"
LOCATION="eastus"

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group=${RESOURCE_GROUP} \
  --workspace-name=${WORKSPACE_NAME} \
  --location=${LOCATION}

echo "✓ Monitoring configured"
```

## Verify Deployment

```bash
#!/usr/bin/env bash
# verify.sh

RESOURCE_GROUP="github-runners-rg"

# List VMs
az vm list \
  --resource-group=${RESOURCE_GROUP} \
  --output table

# Get public IPs
az vm list-ip-addresses \
  --resource-group=${RESOURCE_GROUP} \
  --output table

# Check script execution
az vm run-command invoke \
  --resource-group=${RESOURCE_GROUP} \
  --name=github-runner-0 \
  --command-id=RunShellScript \
  --scripts="tail -100 /var/log/runner-bootstrap.log"

echo "✓ Deployment verified"
```

## Cleanup

```bash
#!/usr/bin/env bash
# cleanup.sh

RESOURCE_GROUP="github-runners-rg"

az group delete \
  --name=${RESOURCE_GROUP} \
  --yes

echo "✓ All resources deleted"
```

## References

- [Azure VM Documentation](https://docs.microsoft.com/azure/virtual-machines/)
- [Virtual Machine Scale Sets](https://docs.microsoft.com/azure/virtual-machine-scale-sets/)
- [Key Vault](https://docs.microsoft.com/azure/key-vault/)
- [Azure Monitor](https://docs.microsoft.com/azure/azure-monitor/)
