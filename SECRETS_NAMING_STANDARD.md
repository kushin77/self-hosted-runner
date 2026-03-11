# Unified Secret Naming Convention Standard

**Version**: 1.0  
**Status**: Enforced  
**Date**: 2026-03-11  

## Overview

All secrets and credentials across the repository **must** follow this standardized naming convention to ensure:
- **Immutability**: Audit trail consistency across GSM, Vault, KMS, and GitHub Secrets
- **Ephemerity**: Easy rotation and cleanup tracking
- **Idempotency**: Safe re-provisioning and re-deployment
- **Automation**: Script-based discovery, rotation, and revocation
- **Security**: Consistent encoding, encryption, and access control

---

## Naming Convention Template

```
PREFIX_PROVIDER_SYSTEM_TYPE_ENVIRONMENT_[QUALIFIER]
```

### Fields

| Field | Valid Values | Example | Notes |
|-------|--------------|---------|-------|
| **PREFIX** | `CREDENTIAL`, `SECRET`, `TOKEN`, `KEY`, `APIKEY` | `CREDENTIAL` | Semantic type of secret |
| **PROVIDER** | `GCP`, `AWS`, `AZURE`, `VAULT`, `DOCKER`, `GH`, `DB`, `OAUTH` | `GCP` | Cloud/service provider |
| **SYSTEM** | `GSM`, `WIF`, `SA`, `IAM`, `ROLE`, `OIDC`, `APPROLE` | `WIF` | Specific subsystem |
| **TYPE** | `ID`, `KEY`, `TOKEN`, `SECRET`, `PASSWORD`, `CERT`, `JWT` | `TOKEN` | Credential type |
| **ENVIRONMENT** | `DEV`, `STAGING`, `PROD` | `PROD` | Deployment environment |
| **QUALIFIER** | Optional suffix for specificity (e.g., role, region, service) | `BACKEND` | Additional context |

---

## Examples by Provider

### Google Cloud (GCP)

```bash
# Workload Identity Federation (WIF) — RECOMMENDED (no static keys)
CREDENTIAL_GCP_WIF_PROVIDER_PROD          # WIF provider ID
CREDENTIAL_GCP_WIF_SA_PROD                # Service account bound to WIF

# Service Account Keys (deprecated, use WIF instead)
CREDENTIAL_GCP_SA_KEY_PROD                # SA key JSON (base64 encoded)
CREDENTIAL_GCP_KMS_KEY_PROD               # KMS crypto key resource path

# Google Secret Manager (GSM)
SECRET_GCP_GSM_ENCRYPTION_KEY_PROD        # KMS key for GSM encryption
APIKEY_GCP_MONITORING_PROD                # Cloud Monitoring API key
```

### AWS

```bash
# OIDC — RECOMMENDED (no static keys)
CREDENTIAL_AWS_OIDC_ROLE_ARN_PROD         # IAM role ARN for GitHub OIDC
TOKEN_AWS_STS_SESSION_PROD                # STS session token (ephemeral)

# Static Keys (deprecated, use OIDC instead)
CREDENTIAL_AWS_ACCESS_KEY_ID_PROD         # ❌ DEPRECATED: IAM user access key
CREDENTIAL_AWS_SECRET_ACCESS_KEY_PROD     # ❌ DEPRECATED: IAM user secret key

# KMS
KEY_AWS_KMS_MASTER_KEY_ID_PROD            # KMS CMK key ID or ARN
KEY_AWS_KMS_DATA_KEY_PROD                 # Data encryption key (ephemeral)
```

### HashiCorp Vault

```bash
# JWT Authentication (RECOMMENDED)
TOKEN_VAULT_JWT_PROD                      # GitHub OIDC JWT token (auto-rotated)
CREDENTIAL_VAULT_JWT_ROLE_PROD            # Vault JWT role name

# AppRole Authentication
CREDENTIAL_VAULT_APPROLE_ID_PROD          # AppRole role ID
SECRET_VAULT_APPROLE_SECRET_PROD          # AppRole secret ID

# Generic Vault Token (legacy)
TOKEN_VAULT_UNSEAL_KEY_PROD               # ❌ DEPRECATED: Unseal key (non-portable)
```

### GitHub

```bash
# Personal Access Tokens (PAT)
TOKEN_GH_PAT_MINIMAL_PROD                 # PAT with minimal scopes
TOKEN_GH_PAT_ACTIONS_PROD                 # PAT for Actions (if needed)

# GitHub App
CREDENTIAL_GH_APP_ID_PROD                 # GitHub App ID
SECRET_GH_APP_PRIVATE_KEY_PROD            # GitHub App private key (PEM)

# OIDC
CREDENTIAL_GH_OIDC_PROVIDER_PROD          # GitHub OIDC provider URL
TOKEN_GH_OIDC_JWT_PROD                    # JWT from GitHub Actions context
```

### Databases

```bash
# PostgreSQL
CREDENTIAL_DB_POSTGRES_USER_PROD          # Database user name
SECRET_DB_POSTGRES_PASSWORD_PROD          # Database password (encrypted at rest)
CREDENTIAL_DB_POSTGRES_HOST_PROD          # Database hostname/connection string

# MongoDB
CREDENTIAL_DB_MONGODB_URI_PROD            # MongoDB connection string (includes auth)

# Redis
CREDENTIAL_DB_REDIS_HOST_PROD             # Redis host
SECRET_DB_REDIS_PASSWORD_PROD             # Redis password (if AUTH required)
```

### Docker & Container Registries

```bash
# Docker Hub
CREDENTIAL_DOCKER_HUB_USERNAME_PROD       # Docker Hub username
SECRET_DOCKER_HUB_TOKEN_PROD              # Docker Hub access token (not password)

# GCP Container Registry
CREDENTIAL_GCP_REGISTRY_SA_KEY_PROD       # GCP SA key for container registry
TOKEN_GCP_REGISTRY_ACCESS_PROD            # Short-lived registry access token

# GitHub Container Registry (GHCR)
TOKEN_GH_REGISTRY_PAT_PROD                # GitHub PAT for GHCR (read/write)
```

### OAuth2 & Third-Party Services

```bash
# Generic OAuth2 Provider
CREDENTIAL_OAUTH_CLIENT_ID_PROD           # OAuth2 client ID
SECRET_OAUTH_CLIENT_SECRET_PROD           # OAuth2 client secret

# Azure Tenant
CREDENTIAL_AZURE_TENANT_ID_PROD           # Azure tenant ID
CREDENTIAL_AZURE_CLIENT_ID_PROD           # Azure service principal client ID
SECRET_AZURE_CLIENT_SECRET_PROD           # Azure service principal secret
```

---

## Storage Locations & Access Patterns

| Secret Name | Preferred Storage | Primary Access | Rotation |
|-------------|-------------------|-----------------|----------|
| `CREDENTIAL_*_PROD` (static) | GSM or Vault KV | Direct retrieval | Monthly+ |
| `TOKEN_*_PROD` (ephemeral) | Vault or environment | OIDC JWT from OIDC provider | Auto (hourly) |
| `SECRET_*_PROD` (encrypted) | Vault transit | Vault `transit/encrypt` | On request |
| `APIKEY_*_PROD` | GSM with KMS | GSM versions API | Quarterly |
| `KEY_*_PROD` (master keys) | AWS KMS / GCP KMS | Cloud provider directly | Quarterly |

---

## Environment Variables in Scripts

When referencing secrets in bash/Python scripts:

```bash
# ✅ CORRECT: Use standardized naming
export CREDENTIAL_GCP_WIF_PROVIDER="${CREDENTIAL_GCP_WIF_PROVIDER_PROD}"
export TOKEN_VAULT_JWT="${TOKEN_VAULT_JWT_PROD}"

# ❌ WRONG: Ad-hoc naming (will cause confusion)
export GCP_WIF_PROVIDER="${..."  # Renamed without pattern
export VAULT_TOKEN="${..."       # Ambiguous "VAULT_TOKEN" (which Vault? which role?)

# ❌ WRONG: Embedded secrets (never acceptable)
export VAULT_UNSEAL_KEY="s.xyz123..."  # Never commit actual values
```

---

## Retrieval Patterns (GSM → Vault → KMS Chain)

### Pattern 1: Direct GSM Retrieval (Simple Credentials)

```bash
#!/usr/bin/env bash
SECRET_NAME="CREDENTIAL_GCP_SA_PROD"
SECRET_VALUE=$(gcloud secrets versions access latest --secret="$SECRET_NAME" --project="nexusshield-prod")
export "${SECRET_NAME}=${SECRET_VALUE}"
```

### Pattern 2: GSM → Vault Sync (Multi-Layer)

```bash
#!/usr/bin/env bash
SECRET_NAME="CREDENTIAL_GCP_SA_PROD"

# Fetch from GSM
gsm_value=$(gcloud secrets versions access latest --secret="$SECRET_NAME")

# Sync to Vault
vault kv put secret/data/gcp value="$gsm_value" \
  --token="$VAULT_TOKEN" \
  --address="$VAULT_ADDR"

# Fetch from Vault for downstream use
vault_retrieved=$(vault kv get -field=value secret/data/gcp)
export "${SECRET_NAME}=${vault_retrieved}"
```

### Pattern 3: JWT / Ephemeral Tokens (OIDC/Vault)

```bash
#!/usr/bin/env bash
# No extraction needed — use token directly from environment or fetch fresh JWT
TOKEN_VAULT_JWT="${TOKEN_VAULT_JWT_PROD:-}"
if [[ -z "$TOKEN_VAULT_JWT" ]]; then
  # Generate fresh JWT from OIDC provider (auto-rotated hourly)
  TOKEN_VAULT_JWT=$(curl -s "https://token.actions.githubusercontent.com?audience=vault" \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}")
fi
export TOKEN_VAULT_JWT
```

---

## Audit & Compliance

### Naming Convention Validation

All ci/cd and deployment scripts must validate secret names before use:

```bash
validate_secret_name() {
  local name="$1"
  # Pattern: ^(CREDENTIAL|SECRET|TOKEN|KEY|APIKEY)_[A-Z]+_[A-Z]+_[A-Z]+_[A-Z]+(_[A-Z]+)?$
  if [[ ! "$name" =~ ^[A-Z]+_[A-Z]+_[A-Z]+_[A-Z]+(_[A-Z]+)?$ ]]; then
    echo "ERROR: Secret name '$name' does not match standard naming convention"
    return 1
  fi
  return 0
}

# Example usage in scripts
for secret in CREDENTIAL_GCP_WIF_PROD TOKEN_VAULT_JWT_PROD; do
  validate_secret_name "$secret" || exit 1
done
```

### Immutable Audit Trail

All secret access/rotation events logged to `.secret-audit/`:

```json
{
  "timestamp": "2026-03-11T16:30:00Z",
  "event": "secret_accessed",
  "secret_name": "CREDENTIAL_GCP_WIF_PROD",
  "source": "scripts/deploy/direct_deploy.sh",
  "action": "read",
  "status": "success",
  "user": "operator",
  "immutable": true
}
```

---

## Migration Path: Old → New Naming

| Old Name | New Name | Provider | Notes |
|----------|----------|----------|-------|
| `GCP_SERVICE_ACCOUNT_KEY` | `CREDENTIAL_GCP_SA_KEY_PROD` | GCP | Base64-encoded JSON |
| `VAULT_TOKEN` | `TOKEN_VAULT_JWT_PROD` | Vault | Prefer JWT (OIDC) |
| `AWS_ACCESS_KEY_ID` | `CREDENTIAL_AWS_OIDC_ROLE_ARN_PROD` | AWS | Migrate to OIDC + STS |
| `DB_PASSWORD` | `SECRET_DB_POSTGRES_PASSWORD_PROD` | Database | Encrypt at rest |
| `DOCKER_HUB_TOKEN` | `TOKEN_DOCKER_HUB_TOKEN_PROD` | Docker | Use token, not password |

---

## Enforcement Rules

1. **All new secrets** must follow naming standard within 24 hours of creation.
2. **All scripts** must reference secrets by standardized names only (validated at runtime).
3. **All documentation** must use standardized names in examples.
4. **All rotations** must audit against the standard naming convention.
5. **All revocations** must track by standardized name in immutable logs.

---

## Related Documentation

- `.instructions.md` — Copilot behavior enforcement (references this standard)
- `POLICY_NO_GITHUB_ACTIONS.md` — No GitHub Actions enforcement
- `ISSUES/no_pull_releases_policy.md` — No PR-based releases
- `scripts/credentials/validate_gsm_vault_kms.sh` — Validation tooling
- `scripts/vault/sync_gsm_to_vault.sh` — GSM→Vault sync pattern

---

**Approved**: Yes ✓  
**Enforced**: Yes ✓  
**Audit**: Automatic via `scripts/utilities/sanitize_secrets.py`
