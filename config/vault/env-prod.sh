#!/bin/bash
# Production Vault Configuration
# Generated: 2026-03-05

export VAULT_ADDR="https://vault.your-domain.com:8200" # ⚠️ PLACEHOLDER: Replace with actual Vault instance URL (e.g., https://vault.mycompany.com:8200)
export VAULT_SKIP_VERIFY="false" # Set to "true" only for dev/test with self-signed certs

# AppRole authentication credentials (provisioner-worker)
# ⚠️ CRITICAL: These are PLACEHOLDERS - never commit real credentials here
# Real values MUST come from secure storage (GitHub Secrets, Vault mount, or environment)
export VAULT_ROLE_ID="<VAULT_ROLE_ID_PLACEHOLDER>" # ⚠️ PLACEHOLDER: Set via GitHub Secrets.VAULT_ROLE_ID or environment variable
# Secret ID is written to /run/vault/.secret via secure volume mount (populated by GitHub Actions)
export VAULT_SECRET_ID_PATH="/run/vault/.secret"

# Provisioner Worker Config
export USE_TERRAFORM_CLI=1
export PROVISIONER_REDIS_URL="redis://localhost:6379"
export PROVISIONER_POLL_MS=5000
export WORKER_MAX_CONCURRENT_JOBS=1

# Service Ports
export MANAGED_AUTH_PORT=4000
export VAULT_SHIM_PORT=4200
export PROVISIONER_METRICS_PORT=9090

echo "✓ Production environment loaded (placeholders configured)"
