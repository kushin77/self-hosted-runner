# Secrets Migration to Vault/GSM/KMS - Implementation Guide

## Overview
This guide documents the complete migration to ephemeral, dynamic secret retrieval using Vault/GSM/KMS with GitHub Actions OIDC token exchange.

### Architecture
- **No long-lived secrets** stored in GitHub repo/org secrets
- **OIDC tokens** exchanged for short-lived Vault/GSM tokens at runtime
- **Immutable, idempotent** deployment workflows
- **Fully automated, hands-off** operation
- **Vault KV v2** engine for secrets storage with versioning and audit logs

## Prerequisites

1. **Vault Instance** running with OIDC auth method enabled
   - Address: `https://vault.example.com` (configured in repo secrets as `VAULT_ADDR`)
   - OIDC endpoint: `https://vault.example.com/v1/auth/oidc/login`

2. **GitHub OIDC Configuration**
   - Vault OIDC role: `github-actions-role` (or custom, set in `VAULT_ROLE`)
   - Role bound to GitHub Actions runner (configured via Vault)

3. **GitHub Repo Secrets** (minimal, only for bootstrap)
   - `VAULT_ADDR`: Vault server address (e.g., `https://vault.example.com`)
   - `VAULT_ROLE`: Vault OIDC role name (e.g., `github-actions-role`)
   - All other secrets: **REMOVED** (to be fetched dynamically)

## Vault Secrets Structure

Store all secrets in Vault KV v2 engine under these paths:

### trivy-webhook/config
Path: `secret/data/trivy-webhook/config`
Fields:
- `webhook_secret`: HMAC secret for validating webhook signatures
- `image_ref`: Container image reference (e.g., `ghcr.io/kushin77/trivy-webhook:latest`)

Example:
```bash
vault kv put secret/trivy-webhook/config \
  webhook_secret="$(openssl rand -hex 32)" \
  image_ref="ghcr.io/kushin77/trivy-webhook:latest"
```

### github/tokens
Path: `secret/data/github/tokens`
Fields:
- `actions_token`: GitHub personal access token (for dispatch events, issue operations)

Example:
```bash
vault kv put secret/github/tokens \
  actions_token="ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
```

### cosign/keys
Path: `secret/data/cosign/keys`
Fields:
- `private_key_b64`: Base64-encoded cosign private key
- `public_key_b64`: Base64-encoded cosign public key
- `rotated_at`: ISO 8601 timestamp of last rotation

Example (auto-managed by rotation workflow):
```bash
vault kv put secret/cosign/keys \
  private_key_b64="$(base64 -w0 < cosign.key)" \
  public_key_b64="$(base64 -w0 < cosign.pub)" \
  rotated_at="2026-03-09T12:00:00Z"
```

### registry/credentials
Path: `secret/data/registry/credentials`
Fields:
- `username`: Registry username (e.g., for GHCR)
- `password`: Registry password or token

Example:
```bash
vault kv put secret/registry/credentials \
  username="kushin77" \
  password="ghcr_XXXXXXXXXXXXXXXXXX"
```

## Workflows

### 1. Bootstrap Vault Secrets (bootstrap-vault-secrets.yml)
One-time setup to initialize secrets in Vault.

**Manual Execution:**
```bash
# Initialize (create default secrets)
gh workflow run bootstrap-vault-secrets.yml -f action=init --repo kushin77/self-hosted-runner

# Update (rotate secrets)
gh workflow run bootstrap-vault-secrets.yml -f action=update --repo kushin77/self-hosted-runner

# Verify (list secret keys)
gh workflow run bootstrap-vault-secrets.yml -f action=verify --repo kushin77/self-hosted-runner
```

### 2. Deploy Trivy Webhook to Staging (deploy-trivy-webhook-staging.yml)
Deploys webhook to worker node at 192.168.168.42 with dynamic secrets from Vault.

**Changes:**
- Requests Vault token via OIDC
- Fetches secrets from Vault
- Applies manifests to worker node
- Supports dry-run for validation

**Execution:**
```bash
# Dry-run (validate only)
gh workflow run deploy-trivy-webhook-staging.yml -f dry_run=true --repo kushin77/self-hosted-runner

# Live deploy
gh workflow run deploy-trivy-webhook-staging.yml -f dry_run=false --repo kushin77/self-hosted-runner
```

### 3. Cosign Key Rotation (cosign-key-rotation.yml)
Rotates cosign keys and stores in Vault.

**Schedule:** Monthly (1st of month, 04:00 UTC)

**Manual Execution:**
```bash
# Dry-run (generate local keys only)
gh workflow run cosign-key-rotation.yml -f dry_run=true --repo kushin77/self-hosted-runner

# Live rotation (generate and store in Vault)
gh workflow run cosign-key-rotation.yml -f dry_run=false --repo kushin77/self-hosted-runner
```

### 4. Trivy Scan & Rebuild (trivy-scan-detect.yml, image-rebuild.yml)
Existing workflows updated to fetch secrets dynamically.

**Changes:**
- Request Vault OIDC token at start
- Fetch cosign key from Vault before signing
- No long-lived secrets in workflow

## Helper Scripts

### scripts/vault_oidc_login.sh
Exchanges GitHub Actions OIDC token for Vault token.

**Usage:**
```bash
bash scripts/vault_oidc_login.sh
# Outputs: VAULT_TOKEN=hvs.XXXXX
```

### scripts/rotate_cosign_keys.sh
Generates cosign key pair and stores in Vault.

**Usage:**
```bash
export VAULT_ADDR="https://vault.example.com"
export VAULT_TOKEN="hvs.XXXXX"
bash scripts/rotate_cosign_keys.sh
```

## Step-by-Step Migration

### Phase 1: Setup (One-time)

1. Configure Vault OIDC with GitHub Actions
2. Set repo secrets: `VAULT_ADDR`, `VAULT_ROLE`
3. Run bootstrap workflow: `gh workflow run bootstrap-vault-secrets.yml -f action=init`
4. Verify secrets in Vault

### Phase 2: Deploy (Repeatable)

1. Trigger staging deploy: `gh workflow run deploy-trivy-webhook-staging.yml -f dry_run=true`
2. Verify logs for successful secret fetch
3. Run live deploy: `gh workflow run deploy-trivy-webhook-staging.yml -f dry_run=false`

### Phase 3: Rotate (Scheduled)

1. Cosign rotation runs monthly automatically
2. Can manually trigger: `gh workflow run cosign-key-rotation.yml -f dry_run=false`
3. Old keys archived in Vault (version history)

## Security Properties

### Immutable
- Secrets versioned in Vault with full audit log
- All operations logged and traceable
- No mutable secret storage

### Ephemeral
- OIDC tokens valid for ~1 hour
- Vault tokens limited lifetime (lease)
- Credentials never persisted to disk post-workflow

### Idempotent
- Workflows can be re-run safely
- Secret fetches are read-only
- Deployments are declarative (kubectl apply idempotency)

### Hands-Off
- All orchestration automated via workflows
- No manual secret management
- No out-of-band credential passing

### No-Ops
- Scheduled workflows run unattended
- Manual triggers available for urgent deployment
- Full audit trail in Vault and GitHub Actions

## Troubleshooting

### OIDC Token Exchange Fails
**Error:** "Could not resolve host: vault.example.com"
**Solution:** Ensure Vault is reachable from GitHub Actions runner; check DNS and firewall

### Secret Not Found in Vault
**Error:** "Secret not found or empty: trivy-webhook/config"
**Solution:** Run bootstrap workflow or manually create secret in Vault

### Deployment Fails with kubeconfig Error
**Error:** "The connection to the server 192.168.168.42 was refused"
**Solution:** Ensure kubeconfig points to correct server; verify worker node is reachable

### Cosign Key Rotation Fails
**Error:** "Key generation failed" or "Vault storage failed"
**Solution:** Check Vault token validity; ensure store path permissions are correct

## Audit and Compliance

All operations logged in:
- **Vault audit logs**: `audit/` endpoint
- **GitHub Actions**: Workflow run logs (encrypted, visible in repo settings)
- **Kubernetes**: Audit logs in etcd if enabled

Query Vault audit for secret access:
```bash
vault audit list
vault audit enable file file_path=/vault/logs/audit.log
```

## Next Steps

1. ✅ Configure Vault OIDC with GitHub Actions
2. ✅ Set repo secrets (VAULT_ADDR, VAULT_ROLE)
3. ✅ Bootstrap secrets: `gh workflow run bootstrap-vault-secrets.yml -f action=init`
4. ✅ Test staging deploy: `gh workflow run deploy-trivy-webhook-staging.yml -f dry_run=true`
5. ✅ Prod deploy and monitor logs

## References

- [Vault OIDC Auth Method](https://www.vaultproject.io/docs/auth/jwt)
- [GitHub Actions OIDC Support](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Vault KV v2 Secrets Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2)
- [About this implementation](./docs/SECRETS_HANDOFF.md)
