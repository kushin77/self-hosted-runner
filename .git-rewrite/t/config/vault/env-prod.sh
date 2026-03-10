#!/bin/bash
# Production Vault Configuration
# Generated: 2026-03-05

export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_SKIP_VERIFY="true"

# AppRole authentication credentials (provisioner-worker)
export VAULT_ROLE_ID="3df2e4bdb7d5ee2005ea65ccbc5d32f3"
# Secret ID is written to /run/vault/.secret via secure volume mount
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

echo "✓ Production environment loaded (test credentials)"
