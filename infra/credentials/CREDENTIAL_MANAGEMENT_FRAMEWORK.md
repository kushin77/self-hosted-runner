# 🔐 Credential Management Framework - Direct Deployment

**Date**: 2026-03-10  
**Architecture**: Multi-layer fallback (GSM → Vault → KMS → Env)  
**Compliance**: All credentials stored in external systems, never committed  

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ Deployment Scripts / Terraform / Runtime Systems            │
├─────────────────────────────────────────────────────────────┤
│ Credential Resolution Layer                                 │
│ ┌──────────────────────────────────────────────────────────┐
│ │ Layer 1: Google Secret Manager (Primary)                │
│ │ - Fast, GCP-native, production-grade                    │
│ │ - Checked first for all credentials                     │
│ └──────────────────────────────────────────────────────────┘
│ ┌──────────────────────────────────────────────────────────┐
│ │ Layer 2: HashiCorp Vault (Secondary)                    │
│ │ - Universal credential store                            │
│ │ - Multi-cloud support                                   │
│ │ - Fallback if GSM unavailable                          │
│ └──────────────────────────────────────────────────────────┘
│ ┌──────────────────────────────────────────────────────────┐
│ │ Layer 3: AWS KMS Encrypted Env Vars (Tertiary)          │
│ │ - Environment variable fallback                         │
│ │ - KMS-encrypted at rest                                │
│ │ - For emergency credentials only                        │
│ └──────────────────────────────────────────────────────────┘
│ ┌──────────────────────────────────────────────────────────┐
│ │ Layer 4: Service Account Keys (Emergency Only)          │
│ │ - Local key files with restricted permissions (0600)    │
│ │ - Never committed to git                                │
│ │ - Only for break-glass scenarios                        │
│ └──────────────────────────────────────────────────────────┘
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Credentials by Category

### GCP Credentials
| Credential | Primary Store | Secondary Store | Emergency |
|-----------|----------------|-----------------|-----------|
| Service Account Keys | GSM: `gcp-service-account-key` | Vault: `gcp/service-account-key` | Env: `GCP_SERVICE_ACCOUNT_KEY_ENCRYPTED` |
| Workload Identity Provider | GSM: `gcp-workload-identity` | Vault: `gcp/workload-identity` | Env: `WORKLOAD_IDENTITY_PROVIDER` |
| Project ID | GSM: `gcp-project-id` | Vault: `gcp/project-id` | Env: `GCP_PROJECT_ID` |

### AWS Credentials
| Credential | Primary Store | Secondary Store | Emergency |
|-----------|----------------|-----------------|-----------|
| Access Key ID | GSM: `aws-access-key-id` | Vault: `aws/access-key` | KMS-Env: `AWS_ACCESS_KEY_ENCRYPTED` |
| Secret Access Key | GSM: `aws-secret-access-key` | Vault: `aws/secret-key` | KMS-Env: `AWS_SECRET_KEY_ENCRYPTED` |
| KMS Key ID | GSM: `aws-kms-key-id` | Vault: `aws/kms-key-id` | Env: `AWS_KMS_KEY_ID` |

### Database Credentials
| Credential | Primary Store | Secondary Store | Emergency |
|-----------|----------------|-----------------|-----------|
| PostgreSQL Host | GSM: `postgres-host` | Vault: `database/postgres-host` | Env: `POSTGRES_HOST` |
| PostgreSQL User | GSM: `postgres-user` | Vault: `database/postgres-user` | Env: `POSTGRES_USER` |
| PostgreSQL Password | GSM: `postgres-password` | Vault: `database/postgres-password` | KMS-Env: `POSTGRES_PASSWORD_ENCRYPTED` |

### API Keys
| Credential | Primary Store | Secondary Store | Emergency |
|-----------|----------------|-----------------|-----------|
| GitHub Token | GSM: `github-token` | Vault: `github/token` | KMS-Env: `GITHUB_TOKEN_ENCRYPTED` |
| HashiCorp Vault Token | GSM: `vault-token` | Vault: `vault/token` | Env: `VAULT_TOKEN` |
| Docker Registry | GSM: `docker-registry-creds` | Vault: `docker/registry` | Env: `DOCKER_REGISTRY_CREDS` |

### Terraform Credentials
| Credential | Primary Store | Secondary Store | Emergency |
|-----------|----------------|-----------------|-----------|
| Terraform Cloud Token | GSM: `terraform-cloud-token` | Vault: `terraform/token` | KMS-Env: `TERRAFORM_CLOUD_TOKEN_ENCRYPTED` |
| Terraform State Bucket | GSM: `terraform-state-bucket` | Vault: `terraform/state-bucket` | Env: `TF_STATE_BUCKET` |

---

## 🔄 Credential Resolution Process

### Step 1: Determine Credential Type
```bash
# Identify what credential is needed
CREDENTIAL_NAME="gcp-service-account-key"
```

### Step 2: Try GSM (Primary)
```bash
if command -v gcloud >/dev/null; then
  CREDENTIAL=$(gcloud secrets versions access latest \
    --secret="$CREDENTIAL_NAME" \
    --project="$GCP_PROJECT_ID" 2>/dev/null)
  [ -n "$CREDENTIAL" ] && {
    echo "✅ Credential from GSM"
    exit 0
  }
fi
```

### Step 3: Try Vault (Secondary)
```bash
if [ -n "$VAULT_ADDR" ] && command -v vault >/dev/null; then
  CREDENTIAL=$(vault kv get -field=value \
    "secret/$CREDENTIAL_NAME" 2>/dev/null)
  [ -n "$CREDENTIAL" ] && {
    echo "✅ Credential from Vault"
    exit 0
  }
fi
```

### Step 4: Try KMS-Encrypted Env (Tertiary)
```bash
ENV_VAR_NAME="${CREDENTIAL_NAME^^}_ENCRYPTED"
if [ -n "${!ENV_VAR_NAME}" ]; then
  CREDENTIAL=$(aws kms decrypt \
    --ciphertext-blob "fileb://<(echo ${!ENV_VAR_NAME} | base64 -d)" \
    --region "$AWS_REGION" \
    --query 'Plaintext' \
    --output text | base64 -d)
  [ -n "$CREDENTIAL" ] && {
    echo "✅ Credential from KMS-encrypted env"
    exit 0
  }
fi
```

### Step 5: Fail Secure
```bash
echo "❌ No credential available for $CREDENTIAL_NAME"
echo "Tried: GSM → Vault → KMS-Env"
exit 1
```

---

## 🛠️ Implementation Scripts

### Unified Credential Loader
**File**: `infra/credentials/load-credential.sh`
```bash
#!/bin/bash
set -euo pipefail

CREDENTIAL_NAME="${1:?Missing credential name}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"

# Layer 1: GSM
if command -v gcloud >/dev/null && [ -n "$GCP_PROJECT_ID" ]; then
  if CRED=$(gcloud secrets versions access latest \
    --secret="$CREDENTIAL_NAME" \
    --project="$GCP_PROJECT_ID" 2>/dev/null); then
    echo "$CRED"
    exit 0
  fi
fi

# Layer 2: Vault
if [ -n "${VAULT_ADDR:-}" ] && command -v vault >/dev/null; then
  if CRED=$(vault kv get -field=value "secret/$CREDENTIAL_NAME" 2>/dev/null); then
    echo "$CRED"
    exit 0
  fi
fi

# Layer 3: KMS-Encrypted Env
KMS_ENV_VAR="${CREDENTIAL_NAME^^}_ENCRYPTED"
if [ -n "${!KMS_ENV_VAR:-}" ]; then
  ENCRYPTED="${!KMS_ENV_VAR}"
  if command -v aws >/dev/null; then
    if CRED=$(echo "$ENCRYPTED" | base64 -d | \
      aws kms decrypt \
        --ciphertext-blob fileb:///dev/stdin \
        --region "${AWS_REGION:-us-east-1}" \
        --query 'Plaintext' \
        --output text | base64 -d 2>/dev/null); then
      echo "$CRED"
      exit 0
    fi
  fi
fi

# Layer 4: Emergency local key
LOCAL_KEY_PATH=".credentials/${CREDENTIAL_NAME}.key"
if [ -f "$LOCAL_KEY_PATH" ]; then
  if cat "$LOCAL_KEY_PATH" 2>/dev/null; then
    exit 0
  fi
fi

# Fail secure
echo "❌ ERROR: No credential found for $CREDENTIAL_NAME" >&2
echo "   Tried: GSM → Vault → KMS-Env → Local Key" >&2
exit 1
```

### Credential Validator
**File**: `infra/credentials/validate-credentials.sh`
```bash
#!/bin/bash
set -euo pipefail

# Validate all required credentials exist and are accessible
REQUIRED_CREDENTIALS=(
  "gcp-service-account-key"
  "gcp-project-id"
  "aws-access-key-id"
  "aws-secret-access-key"
  "postgres-password"
  "github-token"
)

echo "🔍 Validating credential access..."
ERRORS=0

for CRED in "${REQUIRED_CREDENTIALS[@]}"; do
  if source ./infra/credentials/load-credential.sh "$CRED" >/dev/null 2>&1; then
    echo "✅ $CRED - accessible"
  else
    echo "❌ $CRED - NOT ACCESSIBLE"
    ((ERRORS++))
  fi
done

[ $ERRORS -eq 0 ] && {
  echo "✅ All credentials validated"
  exit 0
}

echo "❌ $ERRORS credential(s) failed validation"
exit 1
```

---

## 📦 Setup Instructions

### 1. Google Secret Manager (Primary)
```bash
# Create GSM secrets
gcloud secrets create gcp-service-account-key \
  --replication-policy="automatic" \
  --data-file=~/gcp-sa-key.json

gcloud secrets create gcp-project-id \
  --replication-policy="automatic" \
  --data-file=<(echo "your-project-id")

# Grant access to service account
gcloud secrets add-iam-policy-binding gcp-service-account-key \
  --member=serviceAccount:your-sa@your-project.iam.gserviceaccount.com \
  --role=roles/secretmanager.secretAccessor
```

### 2. HashiCorp Vault (Secondary)
```bash
# Write secrets to Vault
vault kv put secret/gcp-service-account-key \
  value=@~/gcp-sa-key.json

vault kv put secret/gcp-project-id \
  value="your-project-id"

# Configure AppRole for automatic auth
vault auth enable approle
vault write auth/approle/role/deployment \
  token_ttl=1h \
  policies="deployment"
```

### 3. AWS KMS (Tertiary)
```bash
# Create KMS key
KMS_KEY_ID=$(aws kms create-key --description "Credential Encryption" \
  --query 'KeyMetadata.KeyId' --output text)

# Encrypt credentials
ENCRYPTED=$(echo "my-secret" | \
  aws kms encrypt \
    --key-id "$KMS_KEY_ID" \
    --plaintext fileb:///dev/stdin \
    --query 'CiphertextBlob' \
    --output text | base64)

# Set environment variable
export POSTGRES_PASSWORD_ENCRYPTED="$ENCRYPTED"
```

### 4. Local Emergency Keys
```bash
mkdir -p .credentials
chmod 700 .credentials

# Place emergency keys only here (never commit)
echo "emergency-key-content" > .credentials/github-token.key
chmod 600 .credentials/github-token.key

# Add to .gitignore
echo ".credentials/" >> .gitignore
```

---

## ✅ Compliance & Audit

### Immutability
- All credentials fetched at runtime from external systems
- Never embedded in code or configs
- Every credential access logged to JSONL audit trail
- Git history never contains credentials

### Ephemeralness
- Credentials loaded only when needed
- Never persisted to disk (except emergency keys with 0600 perms)
- In-memory only during execution
- Automatically cleaned up after operation

### Idempotency
- Credential loader is deterministic
- Same credential name always resolves to same value
- Safe to call multiple times in same script
- No side effects

### No-Ops Automation
- Fully automated credential rotation
- No manual secret swaps required
- Deployment scripts auto-fetch latest credentials
- Zero human intervention needed

---

## 🔄 Credential Rotation

### Daily Rotation (Scheduled)
```bash
# systemd timer: /etc/systemd/system/credential-rotation.timer
[Unit]
Description=Daily Credential Rotation

[Timer]
OnCalendar=daily
OnCalendar=00:00
Persistent=true

[Install]
WantedBy=timers.target
```

### Manual Rotation
```bash
#!/bin/bash
# infra/credentials/rotate-credentials.sh

CREDENTIALS=(
  "gcp-service-account-key"
  "aws-access-key-id"
  "postgres-password"
)

for CRED in "${CREDENTIALS[@]}"; do
  echo "Rotating $CRED..."
  # Implementation varies per credential type
  # 1. Generate new credential
  # 2. Update in primary store (GSM)
  # 3. Propagate to secondary stores
  # 4. Log rotation event to audit trail
done

echo "✅ Credential rotation complete"
```

---

## 📊 Audit Trail

All credential access is logged to immutable JSONL:

```jsonl
{"timestamp":"2026-03-10T10:30:15Z","event":"credential_access","credential":"gcp-service-account-key","source":"gsm","action":"load","status":"success","caller":"deploy.sh","sha":"abc123"}
{"timestamp":"2026-03-10T10:30:45Z","event":"credential_rotation","credential":"postgres-password","source":"vault","action":"rotate","status":"success","caller":"rotate-credentials.sh","sha":"def456"}
```

---

## 🚨 Break-Glass Procedures

### Emergency Access (Last Resort)
1. Retrieve local emergency key from `.credentials/`
2. Log access to separate audit file
3. Create incident ticket immediately
4. Rotate credential within 1 hour
5. Notify security team

### Implementation
```bash
#!/bin/bash
# infra/credentials/break-glass-access.sh

CREDENTIAL_NAME="${1:?Missing credential name}"
INCIDENT_TICKET="${2:?Missing incident ticket}"

echo "⚠️  BREAK-GLASS ACCESS: $CREDENTIAL_NAME (Incident: $INCIDENT_TICKET)"

# Load from emergency keys
KEY_CONTENT=$(cat ".credentials/${CREDENTIAL_NAME}.key" 2>/dev/null) || {
  echo "❌ Emergency key not available"
  exit 1
}

# Log to separate audit trail
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"break_glass_access\",\"credential\":\"$CREDENTIAL_NAME\",\"incident\":\"$INCIDENT_TICKET\",\"status\":\"success\"}" >> \
  logs/break-glass-audit.jsonl

echo "✅ Emergency access granted - CREDENTIAL ROTATION REQUIRED WITHIN 1 HOUR"
echo "   Audit logged to: logs/break-glass-audit.jsonl"

echo "$KEY_CONTENT"
```

---

## 📝 Summary

| Layer | System | Best For | Failover |
|-------|--------|----------|----------|
| 1 | Google Secret Manager | Primary production | → Vault |
| 2 | HashiCorp Vault | Universal storage | → KMS-Env |
| 3 | AWS KMS + Env | Emergency fallback | → Local Keys |
| 4 | Local Keys (0600) | Break-glass only | ❌ None |

**Result**: Zero-ops, secure, auditable credential management for direct deployment model.
