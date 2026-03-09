#!/usr/bin/env bash
set -euo pipefail

# Helper: show the Vault commands an operator should run to configure auth, policy, and secrets
# This script prints commands only; it does not run them automatically.

cat <<'EOF'
--- Vault setup helper (operator):

# 1. Create policy (reads secrets at secret/data/deployment/fields/*)
vault policy write deployment-fields /path/to/repo/config/vault-policy.hcl

# 2. Enable AWS auth (if using AWS instance role) and map role
vault auth enable aws

# Example: configure aws auth with account ID and partition
vault write auth/aws/config/client secret_key=<> access_key=<>

# Create role mapping: allow instance profile "DeploymentInstanceRole" to assume Vault role
vault write auth/aws/role/deployment-role auth_type=iam bound_iam_principal_arn=arn:aws:iam::ACCOUNT_ID:role/DeploymentInstanceRole policies=deployment-fields ttl=1h

# 3. Write required secrets (example)
vault kv put secret/deployment/fields/VAULT_ADDR value="https://vault.example:8200"
vault kv put secret/deployment/fields/VAULT_ROLE value="deployment"
vault kv put secret/deployment/fields/AWS_ROLE_TO_ASSUME value="arn:aws:iam::111222333444:role/ProvisionRole"
vault kv put secret/deployment/fields/GCP_WORKLOAD_IDENTITY_PROVIDER value="projects/123/locations/global/workloadIdentityPools/pool/providers/provider"

# 4. Verify with an instance having the mapped role: run `vault login -method=aws role=deployment-role` on the VM

EOF
