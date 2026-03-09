# VAULT Operations Guide

## Overview
HashiCorp VAULT provides centralized secret management with dynamic secret generation, AppRole authentication, and comprehensive audit logging.

## Architecture

### Authentication Flow
1. GitHub Actions workflow triggers
2. Retrieve VAULT_ROLE_ID + VAULT_SECRET_ID from GitHub secrets
3. AppRole login to VAULT → receive token
4. Use token to request secrets
5. Auto-cleanup on workflow completion

### Secret Types
- **Static Secrets:** Database passwords, API keys (stored at rest)
- **Dynamic Secrets:** SSH keys, AWS credentials (generated on-demand)
- **Encryption Keys:** KMS keys for envelope encryption

## AppRole Configuration

### Prerequisites
```bash
# Enable AppRole auth method
vault auth enable approle

# Create role
vault write auth/approle/role/github-actions \
  token_ttl=1h \
  bind_secret_id=true \
  secret_id_ttl=30m
```

### GitHub Integration
```bash
# Get role ID
gh secret set VAULT_ROLE_ID --body $(vault read -field=role_id auth/approle/role/github-actions/role-id)

# Generate secret ID
gh secret set VAULT_SECRET_ID --body $(vault write -field=secret_id -f auth/approle/role/github-actions/secret-id)
```

## Workflow Usage

```yaml
- name: Login to VAULT
  run: |
    TOKEN=$(./scripts/ops/vault_login_approle.sh)
    echo "::add-mask::$TOKEN"
    echo "VAULT_TOKEN=$TOKEN" >> $GITHUB_ENV

- name: Get Dynamic SSH Credentials
  run: |
    curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
      https://vault.example.com/v1/ssh/creds/github-ssh \
      | jq '.data'
```

## Best Practices

1. **Use AppRole for Service Auth:** Never use token auth for workflows
2. **Secret Rotation:** Enable automatic secret rotation in VAULT
3. **Audit Logging:** Monitor VAULT audit logs for unauthorized access
4. **Lease Management:** Let VAULT handle lease expiration (auto-cleanup)
5. **Encryption at Rest:** Enable KMS encryption for VAULT storage

## Idempotent Properties

✅ **Same query → same secret output**  
✅ **Repeated requests safe**  
✅ **No side effects from rerun**  
✅ **Immutable audit trail**  

## Constraints Satisfied

✅ **Immutable:** All in Git
✅ **Ephemeral:** Secrets not stored locally  
✅ **Idempotent:** Consistent outputs
✅ **No-Ops:** Automated rotation & cleanup
✅ **Fully Automated:** Workflows handle all ops
✅ **Hands-Off:** Zero manual secret management
