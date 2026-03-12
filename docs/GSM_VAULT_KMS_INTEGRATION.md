# GSM/VAULT/KMS Secret Rotation & Integration Guide

## Overview
All credentials for GitLab CI must be externalized (no hardcoded secrets). This guide covers integration with:
- **Google Secret Manager (GSM)** — Google Cloud Platform
- **HashiCorp Vault** — On-premises/cloud secret management
- **AWS KMS + Secrets Manager** — AWS Key Management Service

All are idempotent, ephemeral, and support automated rotation.

---

## Architecture: Credential Injection at Job Start

```
GitLab CI Pipeline Job
  ├─ before_script: Fetch credentials from GSM/VAULT/KMS
  ├─ Export as $GITLAB_TOKEN, $CI_PROJECT_ID, etc.
  ├─ Run actual job (triage, SLA, bootstrap)
  └─ on_failure: Clean up ephemeral secrets (optional)
```

**Key Principle:** Secrets are fetched fresh on every job run, never persisted in runner storage.

---

## Option A: Google Secret Manager (GSM)

### 1. Setup (One-time, GCP Admin)

```bash
# Create secrets in GSM
gcloud secrets create gitlab-token --replication-policy="automatic"
gcloud secrets create gitlab-project-id --replication-policy="automatic"
gcloud secrets create gitlab-assignee-username --replication-policy="automatic"

# Add secrets
echo -n "YOUR_API_TOKEN" | gcloud secrets versions add gitlab-token --data-file=-
echo -n "NUMERIC_PROJECT_ID" | gcloud secrets versions add gitlab-project-id --data-file=-
echo -n "YOUR_USERNAME" | gcloud secrets versions add gitlab-assignee-username --data-file=-

# Grant access: runner service account reads secrets
gcloud projects get-iam-policy PROJECT_ID --flatten="bindings[].members" --filter="bindings.role:roles/iam.serviceAccountUser"
gcloud secrets add-iam-policy-binding gitlab-token --member=serviceAccount:RUNNER_SA@PROJECT_ID.iam.gserviceaccount.com --role=roles/secretmanager.secretAccessor
```

### 2. Fetch Credentials in `.gitlab-ci.yml` `before_script`

```yaml
variables:
  GITLAB_API_URL: "https://gitlab.com/api/v4"
  GSM_PROJECT_ID: "YOUR_GCP_PROJECT_ID"

before_script:
  - apt-get update && apt-get install -y google-cloud-cli || true
  - gcloud auth activate-service-account --key-file=/path/to/service-account.json || true
  - export GITLAB_TOKEN=$(gcloud secrets versions access latest --secret=gitlab-token --project=${GSM_PROJECT_ID})
  - export CI_PROJECT_ID=$(gcloud secrets versions access latest --secret=gitlab-project-id --project=${GSM_PROJECT_ID})
  - export ASSIGNEE_USERNAME=$(gcloud secrets versions access latest --secret=gitlab-assignee-username --project=${GSM_PROJECT_ID})
```

### 3. Rotation (Automated via GCP Cloud Scheduler)

```bash
# Cloud Scheduler job (daily 2 AM)
gcloud scheduler jobs create pubsub secret-rotation-trigger \
  --location=us-central1 \
  --schedule="0 2 * * *" \
  --topic=secret-rotate-topic \
  --message-body='{"action":"rotate"}'

# Cloud Function listens to topic, rotates secrets
# (Pseudo-code; implement custom rotation logic)
def rotate_secrets(event, context):
    new_token = generate_new_gitlab_token()
    gcloud secrets versions add gitlab-token --data-file=new_token
```

---

## Option B: HashiCorp Vault

### 1. Setup (One-time, Vault Admin)

```bash
# Enable KV secrets engine
vault secrets enable -version=2 kv

# Store secrets
vault kv put secret/gitlab \
  token="YOUR_API_TOKEN" \
  project_id="NUMERIC_PROJECT_ID" \
  assignee_username="YOUR_USERNAME"

# Create policy for GitLab CI runner
vault policy write gitlab-ci - <<EOF
path "secret/data/gitlab" {
  capabilities = ["read"]
}
EOF

# Create AppRole for runner authentication (non-human)
vault auth enable approle
vault write auth/approle/role/gitlab-ci \
  token_ttl=10m \
  token_max_ttl=20m \
  bind_secret_id=false \
  policies="gitlab-ci"

# Get role ID and secret ID
ROLE_ID=$(vault read -field=role_id auth/approle/role/gitlab-ci/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/gitlab-ci/secret-id)
```

### 2. Fetch Credentials in `.gitlab-ci.yml` `before_script`

```yaml
variables:
  VAULT_ADDR: "https://vault.example.com"
  VAULT_ROLE_ID: "YOUR_ROLE_ID"        # Masked CI variable
  VAULT_SECRET_ID: "YOUR_SECRET_ID"    # Masked CI variable

before_script:
  - apt-get update && apt-get install -y curl || true
  
  # Authenticate via AppRole
  - |
    TOKEN=$(curl -sSL -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
      -d "{\"role_id\": \"${VAULT_ROLE_ID}\", \"secret_id\": \"${VAULT_SECRET_ID}\"}" | jq -r '.auth.client_token')
  
  # Fetch secrets
  - |
    SECRETS=$(curl -sSL -H "X-Vault-Token: ${TOKEN}" \
      "${VAULT_ADDR}/v1/secret/data/gitlab" | jq '.data.data')
  
  - export GITLAB_TOKEN=$(echo "$SECRETS" | jq -r '.token')
  - export CI_PROJECT_ID=$(echo "$SECRETS" | jq -r '.project_id')
  - export ASSIGNEE_USERNAME=$(echo "$SECRETS" | jq -r '.assignee_username')
```

### 3. Rotation (Automated via Vault API)

```bash
# Vault CLI: update secrets (idempotent)
vault kv put secret/gitlab \
  token="NEW_TOKEN" \
  project_id="NUMERIC_PROJECT_ID" \
  assignee_username="YOUR_USERNAME"

# Automated: Vault secret engine with rotation (Enterprise feature)
# Or: custom cron job on Vault server that rotates via API
```

---

## Option C: AWS KMS + Secrets Manager

### 1. Setup (One-time, AWS Admin)

```bash
# Create KMS key (if not exists)
KMS_KEY_ID=$(aws kms create-key --description "GitLab CI secrets" --query 'KeyMetadata.KeyId' -o text)

# Create secrets in Secrets Manager (encrypted with KMS)
aws secretsmanager create-secret \
  --name gitlab/token \
  --secret-string "YOUR_API_TOKEN" \
  --kms-key-id ${KMS_KEY_ID}

aws secretsmanager create-secret \
  --name gitlab/project-id \
  --secret-string "NUMERIC_PROJECT_ID" \
  --kms-key-id ${KMS_KEY_ID}

aws secretsmanager create-secret \
  --name gitlab/assignee-username \
  --secret-string "YOUR_USERNAME" \
  --kms-key-id ${KMS_KEY_ID}

# IAM Role for runner: attach policy allowing secretsmanager:GetSecretValue
aws iam attach-role-policy \
  --role-name gitlab-runner-role \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

### 2. Fetch Credentials in `.gitlab-ci.yml` `before_script`

```yaml
variables:
  AWS_REGION: "us-east-1"
  AWS_ROLE_ARN: "arn:aws:iam::ACCOUNT_ID:role/gitlab-runner-role"

before_script:
  - apt-get update && apt-get install -y awscli || true
  
  # Assume role (if cross-account)
  - |
    if [ -n "$AWS_ROLE_ARN" ]; then
      CREDS=$(aws sts assume-role --role-arn $AWS_ROLE_ARN --role-session-name gitlab-ci)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')
    fi
  
  # Fetch secrets
  - export GITLAB_TOKEN=$(aws secretsmanager get-secret-value --secret-id gitlab/token --region ${AWS_REGION} | jq -r '.SecretString')
  - export CI_PROJECT_ID=$(aws secretsmanager get-secret-value --secret-id gitlab/project-id --region ${AWS_REGION} | jq -r '.SecretString')
  - export ASSIGNEE_USERNAME=$(aws secretsmanager get-secret-value --secret-id gitlab/assignee-username --region ${AWS_REGION} | jq -r '.SecretString')
```

### 3. Rotation (Automated via AWS Lambda + EventBridge)

```bash
# Create Lambda function to rotate secrets
# Trigger: EventBridge rule (daily at 2 AM UTC)
# Action: Lambda invokes secretsmanager:PutSecretValue with new token

# Example CLI (manual rotate)
aws secretsmanager update-secret \
  --secret-id gitlab/token \
  --secret-string "NEW_API_TOKEN" \
  --region us-east-1
```

---

## Failover Strategy (Multi-Layer)

Implement fallback: try GSM → if unavailable, try Vault → if unavailable, use masked CI variable as last resort.

```bash
# In before_script
fetch_secret() {
  local secret_name=$1
  
  # Try GSM first
  if command -v gcloud >/dev/null 2>&1; then
    gcloud secrets versions access latest --secret="${secret_name}" 2>/dev/null && return 0
  fi
  
  # Try Vault
  if [ -n "$VAULT_ADDR" ]; then
    curl -sSL -H "X-Vault-Token: ${VAULT_TOKEN}" \
      "${VAULT_ADDR}/v1/secret/data/gitlab" | jq -r ".data.data.${secret_name}" 2>/dev/null && return 0
  fi
  
  # Fallback: masked CI variable (least secure, last resort)
  eval "echo \$${secret_name^^}" && return 0
  
  echo "Failed to fetch secret: ${secret_name}" >&2
  return 1
}

export GITLAB_TOKEN=$(fetch_secret "token")
export CI_PROJECT_ID=$(fetch_secret "project_id")
export ASSIGNEE_USERNAME=$(fetch_secret "assignee_username")
```

---

## Best Practices

1. **Never Log Secrets:** Ensure `jq`, `grep`, and GitLab CI masking hide from logs.
2. **TTL/Expiration:** Secrets expire after 24 hours; fetch fresh on each job.
3. **Rotation Frequency:** Rotate tokens monthly (or per company policy).
4. **Audit Trail:** Log all secret access in GCP Audit Logs, Vault Audit, or CloudTrail.
5. **Least Privilege:** Runner service account has minimal IAM permissions (read-only).
6. **No Persistence:** Never save secrets to disk; keep in environment only.

---

## Integration with `.gitlab-ci.yml`

Update your pipeline to fetch secrets via one of the above methods in `before_script`:

```yaml
stages:
  - validate
  - triage
  - sla
  - bootstrap

variables:
  GITLAB_API_URL: "https://gitlab.com/api/v4"

before_script:
  - apt-get update && apt-get install -y curl jq || true
  # Add your chosen secret-fetch logic here (GSM/Vault/KMS)
  # See options A, B, or C above
  - export GITLAB_TOKEN=$(... fetch from GSM/Vault/KMS ...)
  - export CI_PROJECT_ID=$(... fetch from GSM/Vault/KMS ...)
  - export ASSIGNEE_USERNAME=$(... fetch from GSM/Vault/KMS ...)

validate:ci:
  stage: validate
  image: python:3.11
  script:
    - apt-get install -y curl jq || true
    - chmod +x scripts/gitlab-automation/validate-automation-gitlab.sh
    - SKIP_ISSUE_TEST=true PROJECT_ID=${CI_PROJECT_ID} GITLAB_API_URL=${GITLAB_API_URL} GITLAB_TOKEN=${GITLAB_TOKEN} bash scripts/gitlab-automation/validate-automation-gitlab.sh
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

# ... other jobs inherit before_script
```

---

## Verification

Test secret fetch locally (with proper auth):

```bash
# GSM
gcloud secrets versions access latest --secret=gitlab-token --project=YOUR_GCP_PROJECT

# Vault
curl -sSL -H "X-Vault-Token: $(vault print token)" https://vault.example.com/v1/secret/data/gitlab

# AWS
aws secretsmanager get-secret-value --secret-id gitlab/token --region us-east-1
```

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `fetch_secret: permission denied` | Auth not configured | Check GSM/Vault/AWS IAM role on runner |
| "Secret not found" | Secret doesn't exist in backend | Verify secret was created; check secret name |
| "Rate limited" | Too many API calls | Implement caching (fetch once per job) |
| Secrets visible in CI logs | Masking not enabled | Add `masked: true` in GitLab CI variables |

---

## Summary

Choose one approach (GSM recommended for simplicity, Vault for enterprise control, AWS for AWS-native):
1. Set up secrets in backend (one-time)
2. Update `.gitlab-ci.yml` `before_script` to fetch secrets
3. Implement automated rotation (cron/Lambda/scheduler)
4. Test with first pipeline run
5. Monitor access logs (audit trail)

All three are idempotent, ephemeral, and support zero-downtime rotation.
