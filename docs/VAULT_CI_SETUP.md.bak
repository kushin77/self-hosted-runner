# Vault CI Integration Setup Guide

This document describes how to configure GitHub Secrets for the Vault-backed CI integration in the self-hosted-runner repository.

## Overview

The `p2-managed-auth-vault-integration` workflow supports two modes:

1. **DEV Mode** (default): Uses a temporary Docker-based Vault dev server. Invoked when GitHub Secrets are not configured. No additional setup required for PRs.
2. **PROD Mode**: Uses real Vault credentials (AppRole authentication). Invoked when `VAULT_ADDR` secret is configured. Enables production-like testing and secrets persistence.

## Configuration

### GitHub Secrets to Add

Add the following secrets to your GitHub repository settings (`Settings > Secrets and variables > Actions`):

| Secret | Description | Example |
|--------|-------------|---------|
| `VAULT_ADDR` | Vault server URL | `https://vault.internal.company.com:8200` |
| `VAULT_NAMESPACE` | Vault namespace (optional, defaults to `admin`) | `elevatediq/prod` |
| `VAULT_ROLE_ID` | AppRole Role ID for CI auth | `<VAULT_ROLE_ID_PLACEHOLDER>` |
| `VAULT_SECRET_ID` | AppRole Secret ID (rotate regularly) | `<VAULT_SECRET_ID_PLACEHOLDER>` |

### Vault AppRole Configuration

Follow these steps on the Vault server:

#### 1. Enable AppRole Auth Method
```bash
vault auth enable approle
```

#### 2. Create an AppRole for CI
```bash
vault write auth/approle/role/ci-runnercloud \
  token_policies="ci-runnercloud-policy" \
  token_ttl=1h \
  secret_id_ttl=24h \
  bind_secret_id=true
```

#### 3. Create the CI Policy
```bash
vault policy write ci-runnercloud - <<EOF
path "secret/data/runnercloud/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/runnercloud/*" {
  capabilities = ["list"]
}
EOF
```

#### 4. Generate Role ID and Secret ID
```bash
# Get Role ID
ROLE_ID=$(vault read auth/approle/role/ci-runnercloud/role-id -format=json | jq -r '.data.role_id')

# Generate Secret ID
SECRET_ID=$(vault write -f auth/approle/role/ci-runnercloud/secret-id -format=json | jq -r '.data.secret_id')

echo "VAULT_ROLE_ID=$ROLE_ID"
echo "VAULT_SECRET_ID=$SECRET_ID"
```

#### 5. Add these to GitHub Secrets as `VAULT_ROLE_ID` and `VAULT_SECRET_ID`

### Secret ID Rotation

AppRole Secret IDs should be rotated regularly (recommended: monthly):

```bash
# Generate new Secret ID
NEW_SECRET_ID=$(vault write -f auth/approle/role/ci-runnercloud/secret-id -format=json | jq -r '.data.secret_id')

# Update GitHub Secret
gh secret set VAULT_SECRET_ID --body "$NEW_SECRET_ID"

# Verify
gh secret list | grep VAULT
```

## Workflow Behavior

### Pull Request Workflows
- When `VAULT_ADDR` is not set, uses **DEV mode** (local Docker Vault)
- No special secrets required for testing PRs
- Enables safe integration testing without production credentials

### Main Branch Workflows  
- When `VAULT_ADDR` is set, uses **PROD mode** (real Vault)
- Enables production-like secrets persistence testing
- Suitable for pre-production validation

## Troubleshooting

### AppRole Auth Failure
**Error**: `Vault auth failed: 403 Unexpected response`

**Solution**:
- Verify `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are correct
- Check that the Secret ID has not expired (default: 24h)
- Regenerate Secret ID: `vault write -f auth/approle/role/ci-runnercloud/secret-id`

### TLS Certificate Issues
**Error**: `self-signed certificate in certificate chain`

**Solution** (for dev/internal Vault):
- The workflow uses `rejectUnauthorized: false` for dev endpoints
- For production, ensure valid TLS certificates or update the code

### Namespace Not Found
**Error**: `Vault namespace failed: 404 Not Found`

**Solution**:
- Verify `VAULT_NAMESPACE` matches your Vault configuration
- Default namespace is `admin`
- List available namespaces: `vault namespace list`

## Integration Code

### Backend Switch in secretStore.cjs

The `services/managed-auth/lib/secretStore.cjs` module now supports:
- `SECRETS_BACKEND=vault` → Use Vault KV2 store
- `SECRETS_BACKEND=file` → Use local JSON file
- `SECRETS_BACKEND=memory` (default) → In-memory store

Set via environment variable or workflow secret.

### Usage in Tests

```bash
# DEV mode (local Vault)
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
export SECRETS_BACKEND=memory
bash tests/provision_flow.sh

# PROD mode (real Vault with AppRole)
export VAULT_ADDR=https://vault.internal.com:8200
export VAULT_NAMESPACE=elevatediq/prod
export VAULT_ROLE_ID="<VAULT_ROLE_ID_PLACEHOLDER>"
export VAULT_SECRET_ID="<VAULT_SECRET_ID_PLACEHOLDER>"
export SECRETS_BACKEND=vault
bash tests/provision_flow.sh
```

## Monitoring and Validation

### Run Manual Workflow
To validate Vault integration without pushing:

```bash
gh workflow run p2-vault-integration.yml --ref main
gh run list --workflow=p2-vault-integration.yml --limit=1
```

### Check Vault Audit Log
After workflow runs, verify in Vault:

```bash
# List recent auth attempts
vault audit list
vault read sys/audit

# Check AppRole usage (if audit logging enabled)
vault audit enable file file_path=/vault/logs/audit.log
```

### GitHub Actions Status
- Check workflow runs: `gh workflow view p2-vault-integration.yml`
- View recent logs: `gh run view <run-id> --log`

## Related Documentation

- [Vault AppRole Auth Method](https://www.vaultproject.io/docs/auth/approle)
- [Vault KV2 Secrets Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
