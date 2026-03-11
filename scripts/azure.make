#!/bin/bash

###############################################################################
# Azure Integration Module
# Makefile-compatible commands for Azure setup and credential management
###############################################################################

# ============================================================================
# AZURE SETUP & AUTHENTICATION
# ============================================================================

# Interactive setup: Create tenant-wide service principal
azure/setup:
	@echo "Starting Azure Tenant API interactive setup..."
	@bash scripts/setup-azure-tenant-api.sh

# Quick login: Open browser for interactive Azure login (no setup)
azure/login:
	@echo "Opening Azure login in browser..."
	@az login --use-device-code

# List available subscriptions
azure/subscriptions:
	@az account list --query "[].{id:id, name:name, isDefault:isDefault}" -o table

# Set current subscription (requires SUB_ID variable)
azure/set-subscription:
	@if [ -z "$(SUB_ID)" ]; then \
		echo "Usage: make azure/set-subscription SUB_ID=<subscription-id>"; \
		exit 1; \
	fi
	@az account set --subscription "$(SUB_ID)"
	@echo "Subscription set to: $(SUB_ID)"

# Get current account info
azure/whoami:
	@echo "=== Current Azure Account ===" && \
	az account show --query "{name:name, subscriptionId:id, tenantId:tenantId}" -o json

# ============================================================================
# CREDENTIALS MANAGEMENT
# ============================================================================

# Setup environment variables from secrets
azure/env-setup:
	@source scripts/azure-credentials.sh && setup_azure_env

# Verify credentials work
azure/verify:
	@source scripts/azure-credentials.sh && setup_azure_env && verify_azure_access

# Show current environment variables
azure/env-show:
	@echo "AZURE_TENANT_ID: $${AZURE_TENANT_ID:-NOT SET}"
	@echo "AZURE_CLIENT_ID: $${AZURE_CLIENT_ID:-NOT SET}"
	@echo "AZURE_SUBSCRIPTION_ID: $${AZURE_SUBSCRIPTION_ID:-NOT SET}"
	@echo "AZURE_CLIENT_SECRET: $$([ -n "$${AZURE_CLIENT_SECRET}" ] && echo 'SET' || echo 'NOT SET')"

# Fetch specific secret from GSM
azure/secret-get:
	@if [ -z "$(SECRET)" ]; then \
		echo "Usage: make azure/secret-get SECRET=<secret-name>"; \
		echo "Available: azure-{tenant-id,client-id,client-secret,subscription-id}"; \
		exit 1; \
	fi
	@gcloud secrets versions access latest --secret="$(SECRET)" --project="$(shell gcloud config get-value project)" 2>/dev/null || echo "Secret not found: $(SECRET)"

# List all Azure secrets in GSM
azure/secrets-list:
	@echo "=== Azure Secrets in GSM ===" && \
	gcloud secrets list --filter="name:azure-*" --format="table(name,created)" --project="$(shell gcloud config get-value project)"

# ============================================================================
# RESOURCE DISCOVERY
# ============================================================================

# List all resources in current subscription
azure/resources:
	@az resource list --query "[].{name:name, type:type, location:location, group:resourceGroup}" -o table

# List resource groups
azure/groups:
	@az group list --query "[].{name:name, location:location}" -o table

# List all VMs
azure/vms:
	@az vm list --query "[].{name:name, osType:storageProfile.osDisk.osType, group:resourceGroup}" -o table

# List all Storage Accounts
azure/storage:
	@az storage account list --query "[].{name:name, kind:kind, location:location, group:resourceGroup}" -o table

# List all Key Vaults
azure/keyvaults:
	@az keyvault list --query "[].{name:name, location:location, group:resourceGroup}" -o table

# List all SQL Databases
azure/databases:
	@az sqldb list --query "[].{name:name, location:location, group:resourceGroup}" -o table

# List role assignments
azure/roles:
	@az role assignment list --all --query "[].{principal:principalName, role:roleDefinitionName, scope:scope}" -o table | head -20

# ============================================================================
# OPERATIONS
# ============================================================================

# Create resource group (requires RG_NAME and LOCATION)
azure/rg-create:
	@if [ -z "$(RG_NAME)" ] || [ -z "$(LOCATION)" ]; then \
		echo "Usage: make azure/rg-create RG_NAME=<name> LOCATION=<location>"; \
		echo "Locations: eastus, westus, westeurope, southeastasia, etc."; \
		exit 1; \
	fi
	@az group create --name "$(RG_NAME)" --location "$(LOCATION)"
	@echo "Resource group created: $(RG_NAME)"

# Delete resource group (requires RG_NAME, asks for confirmation)
azure/rg-delete:
	@if [ -z "$(RG_NAME)" ]; then \
		echo "Usage: make azure/rg-delete RG_NAME=<name>"; \
		exit 1; \
	fi
	@echo "WARNING: This will delete resource group: $(RG_NAME)"
	@read -p "Type '$(RG_NAME)' to confirm: " confirm; \
	[ "$$confirm" = "$(RG_NAME)" ] || (echo "Cancelled"; exit 1)
	@az group delete --name "$(RG_NAME)" --yes

# Deploy ARM template (requires TEMPLATE and RG_NAME)
azure/deploy:
	@if [ -z "$(TEMPLATE)" ] || [ -z "$(RG_NAME)" ]; then \
		echo "Usage: make azure/deploy TEMPLATE=<path> RG_NAME=<name> [PARAMS=file.json]"; \
		exit 1; \
	fi
	@az deployment group create \
		--name "deploy-$$(date +%s)" \
		--resource-group "$(RG_NAME)" \
		--template-file "$(TEMPLATE)" \
		$$([ -n "$(PARAMS)" ] && echo "--parameters $(PARAMS)" || echo "")

# ============================================================================
# DOCUMENTATION & HELP
# ============================================================================

# Show setup instructions
azure/help:
	@echo ""; \
	echo "╔════════════════════════════════════════════════════════════╗"; \
	echo "║  Azure Tenant API - Quick Reference                       ║"; \
	echo "╚════════════════════════════════════════════════════════════╝"; \
	echo ""; \
	echo "📋 QUICK START:"; \
	echo "  1. make azure/setup           # Create tenant-wide API"; \
	echo "  2. make azure/verify          # Verify credentials"; \
	echo "  3. make azure/resources       # List resources"; \
	echo ""; \
	echo "🔐 CREDENTIALS:"; \
	echo "  make azure/env-setup          # Load from GSM/Vault"; \
	echo "  make azure/env-show           # Show current env vars"; \
	echo "  make azure/secrets-list       # List all secrets"; \
	echo "  make azure/secret-get SECRET=<name>  # Get one secret"; \
	echo ""; \
	echo "📍 ACCOUNT:"; \
	echo "  make azure/login              # Open interactive login"; \
	echo "  make azure/whoami             # Show current account"; \
	echo "  make azure/subscriptions      # List subscriptions"; \
	echo "  make azure/set-subscription SUB_ID=<id>"; \
	echo ""; \
	echo "💾 RESOURCES:"; \
	echo "  make azure/resources          # List all resources"; \
	echo "  make azure/groups             # List resource groups"; \
	echo "  make azure/vms                # List VMs"; \
	echo "  make azure/storage            # List storage accounts"; \
	echo "  make azure/keyvaults          # List key vaults"; \
	echo "  make azure/databases          # List SQL databases"; \
	echo ""; \
	echo "🔧 OPERATIONS:"; \
	echo "  make azure/rg-create RG_NAME=<name> LOCATION=eastus"; \
	echo "  make azure/rg-delete RG_NAME=<name>"; \
	echo "  make azure/deploy TEMPLATE=<file> RG_NAME=<name>"; \
	echo ""; \
	echo "📚 DOCUMENTATION:"; \
	echo "  docs/AZURE_TENANT_API_SETUP.md     # Full guide"; \
	echo "  docs/AZURE_API_USAGE_EXAMPLES.md   # Code examples"; \
	echo "  docs/AZURE_QUICK_REFERENCE.md      # Quick ref"; \
	echo "  config/azure-tenant-api.json       # Configuration"; \
	echo ""; \
	echo "🔗 DOCS:"; \
	echo "  make azure/docs               # Show documentation"; \
	echo ""

# Show full documentation
azure/docs:
	@bat docs/AZURE_TENANT_API_SETUP.md 2>/dev/null || cat docs/AZURE_TENANT_API_SETUP.md

# Show configuration
azure/config:
	@cat config/azure-tenant-api.json | jq . 2>/dev/null || cat config/azure-tenant-api.json

# Show usage examples
azure/examples:
	@cat docs/AZURE_API_USAGE_EXAMPLES.md

# ============================================================================
# AUDIT & MONITORING
# ============================================================================

# Tail setup logs
azure/logs:
	@ls -lhtr /tmp/azure-setup*.log | tail -1 | awk '{print $$NF}' | xargs tail -50

# Show audit trail
azure/audit:
	@echo "=== Azure Setup Audit Trail ===" && \
	ls -lht logs/azure-setup/ 2>/dev/null | head -5 || echo "No audit logs yet"

# View detailed audit
azure/audit-details:
	@if [ -z "$(FILE)" ]; then \
		ls -lhtr logs/azure-setup/*.jsonl 2>/dev/null | tail -1 | awk '{print $$NF}'; \
	else \
		cat "logs/azure-setup/$(FILE)"; \
	fi | jq . 2>/dev/null || echo "No audit data"

# ============================================================================
# HEALTH CHECKS
# ============================================================================

# Full health check
azure/health-check:
	@echo "=== Azure Tenant API Health Check ===" && \
	echo "" && \
	echo "✓ CLI Check:" && \
	az --version 2>/dev/null | head -1 || echo "  ✗ Azure CLI not found" && \
	echo "" && \
	echo "✓ Authentication:" && \
	az account show --query "{name:name, subscriptionId:id}" -o json 2>/dev/null || echo "  ✗ Not authenticated" && \
	echo "" && \
	echo "✓ Secrets (GSM):" && \
	gcloud secrets list --filter="name:azure-*" --format="table(name)" --project="$$(gcloud config get-value project)" 2>/dev/null | wc -l | xargs echo "  Found" || echo "  ✗ Secrets not found" && \
	echo "" && \
	echo "✓ Vault:" && \
	( vault kv list secret/azure 2>/dev/null && echo "  Connected" ) || echo "  ✗ Not connected (optional)" && \
	echo ""

.PHONY: azure/* azure/help azure/docs azure/examples azure/config azure/logs azure/audit
