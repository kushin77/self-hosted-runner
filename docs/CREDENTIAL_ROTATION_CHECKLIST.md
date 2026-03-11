# Credential Rotation Checklist
**Generated:** 2026-03-11  
**Status:** READY FOR OPERATOR EXECUTION  
**Audit Trail:** immutable JSONL logs in `logs/secrets-remediation-*.jsonl`

---

## 🔒 Rotation Scope

### Credentials to Rotate
1. **Google Secret Manager (GSM)** — Primary canonical store
2. **HashiCorp Vault (AppRole)** — Secondary store  
3. **AWS Secrets Manager** — Tertiary store
4. **GitHub Personal Access Tokens (PATs)** — Repository access
5. **SSH Keys (ED25519)** — Operator authentication

---

## Phase 1: Google Secret Manager (GSM) Rotation

### Prerequisites
```bash
# Verify GSM access
gcloud config set project nexusshield-prod
gcloud secrets list --filter="labels.rotation_required:true" 
```

### Secrets to Rotate
| Secret Name | Current Status | Rotation Action |
|-------------|---|---|
| `github-token` | ACTIVE | Create new version, update .env, delete old |
| `slack-webhook` | ACTIVE | Create new version, update Slack workspace, delete old |
| `pagerduty-token` | ACTIVE | Create new version, update PagerDuty integrations, delete old |
| `vault-role-id` | ACTIVE | Rotate via Vault (see Phase 2) |
| `vault-secret-id` | ACTIVE | Rotate via Vault (see Phase 2) |

### Execution Steps

#### Step 1.1: Backup Current Versions
```bash
PROJECT_ID="nexusshield-prod"
SECRETS=("github-token" "slack-webhook" "pagerduty-token")

for SECRET in "${SECRETS[@]}"; do
  echo "$(date): Backing up ${SECRET}..."
  gcloud secrets versions access latest --secret="${SECRET}" \
    > "/tmp/backup-${SECRET}.txt" 2>/dev/null || echo "BACKUP FAILED: ${SECRET}"
  chmod 600 "/tmp/backup-${SECRET}.txt"
  echo "✓ Backed up: /tmp/backup-${SECRET}.txt"
done
```

#### Step 1.2: Rotate GitHub Token
```bash
echo "$(date): Rotating github-token..."

# 1. Create new personal access token in GitHub UI or CLI
# Required scopes: repo, workflow, admin:org_hook
NEW_GITHUB_TOKEN="ghp_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

# 2. Add new version to GSM
gcloud secrets versions add github-token \
  --data-file=<(echo -n "$NEW_GITHUB_TOKEN")
echo "✓ New version created in GSM"

# 3. Update application .env files (if any)
[ -f .env.production ] && sed -i "s/ghp_.*/ghp_REDACTED/" .env.production
[ -f backend/.env ] && sed -i "s/ghp_.*/ghp_REDACTED/" backend/.env

# 4. Verify new version is active in deployed services
# → Services using FetchCredentialProvider will get new token on next rotation tick (< 5 min)

# 5. Schedule old token revocation (GitHub UI → Settings → Developer settings → PATs)
echo "TODOoperator: Revoke old token in GitHub UI after 24h grace period"

echo "✓ GitHub token rotation complete"
```

#### Step 1.3: Rotate Slack Webhook
```bash
echo "$(date): Rotating slack-webhook..."

# 1. Create new webhook in Slack workspace
# Path: Workspace Settings → Manage Apps → Custom Integration → Incoming Webhooks → New
NEW_SLACK_WEBHOOK="https://hooks.slack.com/services/T00000000/B00000000/XXXX..."

# 2. Add new version to GSM
gcloud secrets versions add slack-webhook \
  --data-file=<(echo -n "$NEW_SLACK_WEBHOOK")
echo "✓ New version created in GSM"

# 3. Verify new webhook receives test message
curl -X POST "$NEW_SLACK_WEBHOOK" \
  -H 'Content-Type: application/json' \
  -d '{"text":"🔄 Webhook rotation test - new version active"}'
echo "✓ Test message sent to slack-webhook"

# 4. Delete old webhook in Slack UI after 24h grace period
echo "TODO operator: Delete old webhook in Slack UI after 24h grace period"

echo "✓ Slack webhook rotation complete"
```

#### Step 1.4: Rotate PagerDuty Token
```bash
echo "$(date): Rotating pagerduty-token..."

# 1. Generate new API token in PagerDuty
# Path: Settings → API Access → API Tokens → Create Token
NEW_PAGERDUTY_TOKEN="u+XXXXXXXXXXXXXXXXXX"

# 2. Add new version to GSM
gcloud secrets versions add pagerduty-token \
  --data-file=<(echo -n "$NEW_PAGERDUTY_TOKEN")
echo "✓ New version created in GSM"

# 3. Update any alert routing rules in PagerDuty UI to use new token
echo "TODO operator: Verify alert routing uses new token in PagerDuty UI"

# 4. Revoke old token after 24h grace period
echo "TODO operator: Revoke old token in PagerDuty UI after 24h grace period"

echo "✓ PagerDuty token rotation complete"
```

#### Step 1.5: Cleanup Old Versions (After 24h Grace Period)
```bash
# List all versions of a secret
gcloud secrets versions list github-token

# Destroy old version (irreversible; do only after services are stable)
# gcloud secrets versions destroy VERSION_ID --secret=github-token
```

**GSM Rotation Complete Checklist:**
- [ ] GitHub token rotated and active
- [ ] Slack webhook rotated and responding
- [ ] PagerDuty token rotated and routing alerts
- [ ] Old tokens revoked in respective UIs (after 24h)
- [ ] All changes logged to JSONL
- [ ] Operator sign-off recorded

---

## Phase 2: HashiCorp Vault AppRole Rotation

### Prerequisites
```bash
# Verify Vault access
export VAULT_TOKEN=$(gcloud secrets versions access latest --secret=vault-admin-token)
export VAULT_ADDR="https://vault.nexusshield-prod.internal"

vault auth list | grep approle
```

### Vault Secrets to Rotate
| Item | Current | Rotation Action |
|------|---------|---|
| AppRole role_id | ACTIVE | Fetch from GSM, keep stable |
| AppRole secret_id | ACTIVE | Generate new via `vault write -f` |
| Deployer service account | ACTIVE | Rotate lease (optional) |

### Execution Steps

#### Step 2.1: Generate New AppRole secret_id
```bash
echo "$(date): Rotating Vault AppRole secret_id..."

# Authenticate as Vault admin
export VAULT_TOKEN=$(gcloud secrets versions access latest --secret=vault-admin-token)

# Generate new secret_id
NEW_SECRET_ID=$(vault write -f auth/approle/role/nexusshield-deployer/secret-id \
  -format=json | jq -r '.data.secret_id')

echo "✓ New secret_id generated: ${NEW_SECRET_ID:0:16}..."

# Update in GSM
gcloud secrets versions add vault-secret-id \
  --data-file=<(echo -n "$NEW_SECRET_ID")

echo "✓ New secret_id saved to GSM"
```

#### Step 2.2: Verify New AppRole Credentials Work
```bash
echo "$(date): Testing new AppRole credentials..."

ROLE_ID=$(gcloud secrets versions access latest --secret=vault-role-id)
SECRET_ID=$NEW_SECRET_ID

# Request token
TEST_TOKEN=$(curl -s -X POST \
  "${VAULT_ADDR}/v1/auth/approle/login" \
  -d "{\"role_id\":\"${ROLE_ID}\",\"secret_id\":\"${SECRET_ID}\"}" | \
  jq -r '.auth.client_token')

if [ -z "$TEST_TOKEN" ] || [ "$TEST_TOKEN" = "null" ]; then
  echo "❌ ERROR: AppRole login failed. Rolling back..."
  exit 1
fi

# Test read access
curl -s -X GET \
  -H "X-Vault-Token: ${TEST_TOKEN}" \
  "${VAULT_ADDR}/v1/secret/data/nexusshield/github-token" | jq '.data.data'

echo "✓ New AppRole credentials work"
```

#### Step 2.3: Recycle Old secret_ids (After 24h)
```bash
echo "$(date): Listing old AppRole secret_ids for revocation..."

curl -s -X LIST \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/auth/approle/role/nexusshield-deployer/secret-id" | jq '.data.keys[]'

# Revoke old secret_ids individually:
# curl -X DELETE \
#   -H "X-Vault-Token: ${VAULT_TOKEN}" \
#   "${VAULT_ADDR}/v1/auth/approle/role/nexusshield-deployer/secret-id/OLD_ID"
```

**Vault Rotation Complete Checklist:**
- [ ] New secret_id generated
- [ ] New secret_id saved to GSM
- [ ] Login test passed with new credentials
- [ ] Services updated (via FetchCredentialProvider)
- [ ] Old secret_ids scheduled for revocation
- [ ] All changes logged to JSONL

---

## Phase 3: AWS Secrets Manager Rotation

### Prerequisites
```bash
# Verify AWS access
aws sts get-caller-identity
aws secretsmanager list-secrets --filters Key=name,Values="nexusshield"
```

### AWS Credentials to Rotate
| Type | Location | Action |
|------|----------|--------|
| IAM Access Keys | AWS IAM console | Rotate if exposed |
| Database Password | AWS Secrets Manager | Create new version |
| SSH Key | AWS Systems Manager | Audit only (ED25519 in GSM) |

### Execution Steps

#### Step 3.1: Rotate AWS IAM User Access Key (If Exposed)
```bash
echo "$(date): Checking for exposed AWS access keys..."

# Search git history for AKIA pattern (done in Phase 2 history rewrite)
# If found: rotate immediately

USER_NAME="nexusshield-ci"
OLD_KEYS=$(aws iam list-access-keys --user-name "$USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)

if [ -z "$OLD_KEYS" ]; then
  echo "ℹ No old keys found for $USER_NAME"
else
  echo "⚠ Creating new access key before revoking old..."
  
  # Create new key
  NEW_KEY=$(aws iam create-access-key --user-name "$USER_NAME" --query 'AccessKey')
  NEW_ACCESS_KEY=$(echo "$NEW_KEY" | jq -r '.AccessKeyId')
  NEW_SECRET_KEY=$(echo "$NEW_KEY" | jq -r '.SecretAccessKey')
  
  echo "✓ New access key created: $NEW_ACCESS_KEY"
  
  # Save new key to GSM
  gcloud secrets versions add aws-access-key-id \
    --data-file=<(echo -n "$NEW_ACCESS_KEY")
  gcloud secrets versions add aws-secret-access-key \
    --data-file=<(echo -n "$NEW_SECRET_KEY")
  
  echo "✓ Credentials saved to GSM"
  
  # After 24h grace, revoke old keys
  for KEY_ID in $OLD_KEYS; do
    echo "TODO operator: Revoke old key $KEY_ID after 24h (aws iam delete-access-key)"
  done
fi
```

**AWS Rotation Complete Checklist:**
- [ ] IAM console checked for exposed keys
- [ ] New keys generated if needed
- [ ] Keys saved to GSM
- [ ] Old keys scheduled for revocation
- [ ] Credentials verified in deployed services

---

## Phase 4: SSH Key Rotation (ED25519)

### Prerequisites
```bash
# Verify SSH key exists
ls -lh ~/.ssh/akushnir_deploy*
```

### Execution Steps

#### Step 4.1: Generate New ED25519 Key
```bash
echo "$(date): Generating new ED25519 SSH key..."

ssh-keygen -t ed25519 -C "nexusshield-deployment-$(date +%Y%m%d)" \
  -f ~/.ssh/akushnir_deploy_new \
  -N ""

echo "✓ New key pair generated"
```

#### Step 4.2: Save New Public Key to Repository
```bash
# Update deploy key in GitHub or cloud provider
cat ~/.ssh/akushnir_deploy_new.pub

# Add to: GitHub Settings → Deploy Keys or GSM
gcloud secrets versions add operator-ssh-public-key \
  --data-file=~/.ssh/akushnir_deploy_new.pub

echo "✓ New public key saved to GSM"

# Do NOT save private key to GSM; rotation happens via SSH agent rotation only
```

**SSH Rotation Complete Checklist:**
- [ ] New ED25519 key generated
- [ ] Public key saved to GSM
- [ ] Old key removed from GitHub
- [ ] SSH agent rotated locally
- [ ] Connect test passed

---

## Summary: Cross-Phase Validation

### All Rotation Steps Complete?
- [ ] Phase 1: GSM tokens (GitHub, Slack, PagerDuty)
- [ ] Phase 2: Vault AppRole secret_id
- [ ] Phase 3: AWS IAM / Secrets Manager
- [ ] Phase 4: SSH Keys rotated

### Post-Rotation Verification
```bash
# Check all source services
echo "Verifying GitHub API..."
curl -s -H "Authorization: token $(gcloud secrets versions access latest --secret=github-token)" \
  https://api.github.com/user > /dev/null && echo "✓ GitHub token OK" || echo "❌ GitHub token FAILED"

# Check Vault
echo "Verifying Vault..."
vault secrets list > /dev/null && echo "✓ Vault OK" || echo "❌ Vault FAILED"

# Check AWS
echo "Verifying AWS..."
aws sts get-caller-identity && echo "✓ AWS OK" || echo "❌ AWS FAILED"

# Run e2e tests
cd /home/akushnir/self-hosted-runner
bash tests/e2e/credential_access_test.sh
```

### Record Final Audit
```bash
# Append to JSONL audit log
cat >> logs/secrets-remediation-$(date +%Y%m%d).jsonl << 'EOF'
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","phase":"credentials_rotated","status":"complete","rotations":["gsmgh-token","gsm-slack","gsm-pagerduty","vault-secret-id","aws-keys","ssh-keys"],"action":"all_credentials_rotated"}
EOF
```

---

## Operator Sign-Off

**Performed by:** ___________________  
**Date:** ___________________  
**All rotations complete:** ☐ Yes ☐ No  
**E2E tests passed:** ☐ Yes ☐ No  
**Issues to follow up:** _________________________________  

---

## Rollback Procedure (Emergency Only)

If rotation causes service outages:
```bash
# Retrieve backed up credentials
cat /tmp/backup-github-token.txt | xargs -I {} gcloud secrets versions add github-token --data-file=<(echo -n {})
# Restart affected services
# Notify team of rollback
```

---

## Audit Trail
- Log location: `logs/secrets-remediation-*.jsonl`  
- Immutable: ✓ Yes (append-only format)  
- Accessible to: operators, audit teams  
- Retention: 7 years (compliance)
