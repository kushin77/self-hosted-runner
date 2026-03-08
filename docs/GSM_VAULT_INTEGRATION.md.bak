# GCP Secret Manager (GSM) and Vault AppRole Integration

This document describes the integration of Google Cloud Secret Manager (GSM) and HashiCorp Vault with the self-hosted runner automation for secure, rotatable credential management.

## Overview

The system uses two complementary secrets stores:
1. **GCP Secret Manager (GSM)**: Primary store for GitHub secrets (`RUNNER_MGMT_TOKEN`, `DEPLOY_SSH_KEY`, etc.)
2. **HashiCorp Vault**: AppRole-based authentication for CI/CD; supports automated rotation.

## GCP Secret Manager (GSM) Integration

### Purpose
GSM provides a centralized, auditable secrets store with granular IAM controls. All runner management credentials are stored here and synced to GitHub Actions secrets.

### Setup Steps

1. **Authenticate with GCP**:
   ```bash
   gcloud auth login
   gcloud config set project <YOUR_GCP_PROJECT_ID>
   ```

2. **Create GSM secrets**:
   ```bash
   # RUNNER_MGMT_TOKEN: GitHub PAT with 'administration:read' scope
   echo -n "$RUNNER_MGMT_TOKEN" | gcloud secrets create runner-mgmt-token --data-file=-
   
   # DEPLOY_SSH_KEY: Private SSH key for Ansible/automated recovery
   gcloud secrets create deploy-ssh-key --data-file=~/.ssh/id_ed25519
   
   # MINIO_ENDPOINT: MinIO S3-compatible endpoint
   echo -n "http://mc.elevatediq.ai:9000" | gcloud secrets create minio-endpoint --data-file=-
   
   # MINIO credentials
   echo -n "$MINIO_ACCESS_KEY" | gcloud secrets create minio-access-key --data-file=-
   echo -n "$MINIO_SECRET_KEY" | gcloud secrets create minio-secret-key --data-file=-
   ```

3. **Set up IAM bindings**:
   ```bash
   # Grant the service account read access to all runner secrets
   SA="<YOUR_SERVICE_ACCOUNT_EMAIL>"
   gcloud secrets add-iam-policy-binding runner-mgmt-token --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
   gcloud secrets add-iam-policy-binding deploy-ssh-key --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
   gcloud secrets add-iam-policy-binding minio-endpoint --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
   gcloud secrets add-iam-policy-binding minio-access-key --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
   gcloud secrets add-iam-policy-binding minio-secret-key --member=serviceAccount:$SA --role=roles/secretmanager.secretAccessor
   ```

4. **Sync to GitHub Actions**:
   A scheduled workflow (`.github/workflows/sync-gsm-to-github-secrets.yml`) automatically pulls secrets from GSM and updates GitHub Actions repository secrets every 6 hours, or on-demand:
   ```bash
   gh workflow run sync-gsm-to-github-secrets.yml
   ```

### Accessing GSM Secrets in Workflows

In GitHub Actions workflows, use the `gcloud secrets versions access` command:
```yaml
- name: Fetch runner token from GSM
  run: |
    RUNNER_MGMT_TOKEN=$(gcloud secrets versions access latest --secret="runner-mgmt-token")
    echo "::add-mask::$RUNNER_MGMT_TOKEN"
    echo "RUNNER_MGMT_TOKEN=$RUNNER_MGMT_TOKEN" >> $GITHUB_ENV
```

## HashiCorp Vault AppRole Integration

### Purpose
Vault provides dynamic credential generation and automated rotation for long-lived secrets, reducing the blast radius of compromised credentials.

### Setup Steps

1. **Install and configure Vault CLI**:
   ```bash
   vault login -method=oidc role=gh-runner
   ```

2. **Create AppRole with policy**:
   ```bash
   # Enable AppRole auth method
   vault auth enable approle
   
   # Create policy for runner credentials
   vault policy write runner-policy - <<EOF
   path "secret/data/runner/*" {
     capabilities = ["read", "list"]
   }
   path "kv/data/runner/*" {
     capabilities = ["read", "list"]
   }
   EOF
   
   # Create AppRole
   vault write auth/approle/role/gh-runner \
     token_ttl=3600 \
     token_max_ttl=86400 \
     policies="runner-policy"
   
   # Get role ID and generate secret ID
   ROLE_ID=$(vault read -field=role_id auth/approle/role/gh-runner/role-id)
   SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/gh-runner/secret-id)
   
   echo "VAULT_ROLE_ID=$ROLE_ID"
   echo "VAULT_SECRET_ID=$SECRET_ID"
   ```

3. **Store AppRole credentials in GitHub Secrets**:
   ```bash
   gh secret set VAULT_ADDR --body "https://vault.elevatediq.ai:8200"
   gh secret set VAULT_ROLE_ID --body "$ROLE_ID"
   gh secret set VAULT_SECRET_ID --body "$SECRET_ID"
   ```

4. **Store credentials in Vault**:
   ```bash
   vault kv put secret/runner/mgmt-token value="$RUNNER_MGMT_TOKEN"
   vault kv put secret/runner/ssh-key value=@~/.ssh/id_ed25519
   vault kv put secret/runner/minio-endpoint value="http://mc.elevatediq.ai:9000"
   vault kv put secret/runner/minio-access-key value="$MINIO_ACCESS_KEY"
   vault kv put secret/runner/minio-secret-key value="$MINIO_SECRET_KEY"
   ```

### Accessing Vault Secrets in Workflows

In GitHub Actions workflows, authenticate and fetch secrets:
```yaml
- name: Authenticate with Vault
  run: |
    # Login using AppRole
    TOKEN=$(curl -s -X POST \
      -d '{"role_id":"'$VAULT_ROLE_ID'","secret_id":"'$VAULT_SECRET_ID'"}' \
      $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token')
    
    # Fetch credentials
    RUNNER_MGMT_TOKEN=$(curl -s -H "X-Vault-Token: $TOKEN" \
      $VAULT_ADDR/v1/secret/data/runner/mgmt-token | jq -r '.data.data.value')
    
    echo "::add-mask::$RUNNER_MGMT_TOKEN"
    echo "RUNNER_MGMT_TOKEN=$RUNNER_MGMT_TOKEN" >> $GITHUB_ENV
  env:
    VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
    VAULT_ROLE_ID: ${{ secrets.VAULT_ROLE_ID }}
    VAULT_SECRET_ID: ${{ secrets.VAULT_SECRET_ID }}
```

## AppRole Rotation

Automatic rotation of AppRole credentials is essential to minimize the impact of leaked credentials.

### Scheduled Rotation Workflow

A workflow (`.github/workflows/rotate-vault-approle.yml`) runs monthly to generate new AppRole credentials:

```yaml
name: Rotate Vault AppRole
on:
  schedule:
    - cron: '0 2 1 * *'  # First of every month
  workflow_dispatch: {}

jobs:
  rotate:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: Authenticate to Vault
        run: |
          TOKEN=$(curl -s -X POST \
            -d '{"role_id":"'$VAULT_ROLE_ID'","secret_id":"'$VAULT_SECRET_ID'"}' \
            $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token')
          echo "::add-mask::$TOKEN"
          echo "VAULT_TOKEN=$TOKEN" >> $GITHUB_ENV
      
      - name: Rotate secret ID
        run: |
          NEW_SECRET_ID=$(curl -s -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            $VAULT_ADDR/v1/auth/approle/role/gh-runner/secret-id | jq -r '.data.secret_id')
          
          # Update GitHub secret
          gh secret set VAULT_SECRET_ID --body "$NEW_SECRET_ID"
          
          # Issue notification
          gh issue create \
            --title "Vault AppRole credentials rotated successfully" \
            --body "New VAULT_SECRET_ID generated and stored. Old credentials invalidated."
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          VAULT_ROLE_ID: ${{ secrets.VAULT_ROLE_ID }}
          VAULT_SECRET_ID: ${{ secrets.VAULT_SECRET_ID }}
          GH_TOKEN: ${{ github.token }}
```

## Emergency Credential Recovery

If credentials are compromised:

1. **Immediate**: Revoke the AppRole secret:
   ```bash
   vault write -f auth/approle/role/gh-runner/secret-id/lookup/destroy secret_id="$COMPROMISED_SECRET_ID"
   ```

2. **Short-term**: Rotate AppRole credentials:
   ```bash
   NEW_SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/gh-runner/secret-id)
   gh secret set VAULT_SECRET_ID --body "$NEW_SECRET_ID"
   ```

3. **Long-term**: Rotate the underlying runner management token (PAT) and SSH keys via the `credential-rotation` workflow.

## Audit and Monitoring

### GSM Audit Logs
View all GSM access in the GCP Cloud Audit Logs:
```bash
gcloud logging read "resource.type=secretmanager.googleapis.com" --limit=50
```

### Vault Audit Logs
Enable and review Vault audit logs:
```bash
vault audit enable file file_path=/var/log/vault/audit.log
vault audit list
```

## Integration with Self-Heal Workflow

The `runner-self-heal.yml` workflow uses Vault credentials:
```yaml
- name: Fetch credentials from Vault
  run: |
    RUNNER_MGMT_TOKEN=$(curl -s -X POST \
      -d '{"role_id":"'$VAULT_ROLE_ID'","secret_id":"'$VAULT_SECRET_ID'"}' \
      $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token' | \
      xargs -I {} curl -s -H "X-Vault-Token: {}" \
      $VAULT_ADDR/v1/secret/data/runner/mgmt-token | jq -r '.data.data.value')
```

## Testing

To verify GSM and Vault integration:

```bash
# Test GSM access
gcloud secrets versions access latest --secret="runner-mgmt-token"

# Test Vault access
vault login -method=oidc role=gh-runner
vault kv get secret/runner/mgmt-token

# Run tests in CI
gh workflow run test-secrets-integration.yml
```

## Troubleshooting

- **GSM permission denied**: Ensure service account has `roles/secretmanager.secretAccessor` on all secrets.
- **Vault auth failure**: Verify AppRole credentials in GitHub Secrets and Vault role policies.
- **Secret rotation failed**: Check Vault audit logs for errors; may need manual secret ID refresh.

## References

- [GCP Secret Manager Docs](https://cloud.google.com/secret-manager/docs)
- [HashiCorp Vault AppRole Auth](https://www.vaultproject.io/docs/auth/approle)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
