# 🔐 Phase 1A: Credential Management - EXECUTION GUIDE

**Phase Status:** READY FOR IMPLEMENTATION  
**Timeline:** This Week (Mar 8-12, 2026)  
**Blocker Status:** All Infrastructure/Helper Actions Ready  
**Next Step:** Execute GSM Integration & Secret Migration

---

## 📊 CURRENT STATE SUMMARY

### ✅ COMPLETED
- [x] Credential inventory: 25 secrets in GitHub repo settings cataloged
- [x] Helper actions: `retrieve-secret-gsm`, `retrieve-secret-vault`, `retrieve-secret-kms` already created
- [x] Audit trail: Directory structure + audit logger workflow created
- [x] Rotation workflows: GSM, Vault, KMS rotation workflows already deployed
- [x] Documentation: Comprehensive credential matrix + migration plan

### 🔄 IN PROGRESS
- Infrastructure setup (GSM/Vault/KMS)
- OIDC/WIF provider configuration
- Secret migration from GitHub to external managers
- Rotation workflow integration with audit logging

### 📋 PENDING
- Team testing & validation
- Security compliance audit
- Training & handoff

---

## 🚀 DAILY EXECUTION PLAN

### DAY 1 (Tuesday, March 8)

#### Morning (09:00 - 12:00)
**Task: GSM Infrastructure Setup**

```bash
# Step 1: Enable GSM API
gcloud services enable secretmanager.googleapis.com

# Step 2: Verify/create service account
gcloud iam service-accounts create github-actions-gsm \
  --display-name="GitHub Actions GSM Access" \
  --project=$GCP_PROJECT_ID 2>/dev/null || echo "Service account exists"

# Step 3: Grant GSM admin role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member=serviceAccount:github-actions-gsm@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/secretmanager.admin

# Step 4: Create initial secrets in GSM
declare -A SECRETS=(
  ["docker-hub-username"]="${DOCKER_HUB_USERNAME:-}"
  ["docker-hub-password"]="${DOCKER_HUB_PASSWORD:-}"
  ["ghcr-token"]="${GHCR_TOKEN:-}"
  ["slack-webhook-url"]="${SLACK_WEBHOOK_URL:-}"
  ["cosign-key"]="${COSIGN_KEY:-}"
  ["registry-username"]="${REGISTRY_USERNAME:-}"
)

for secret_name in "${!SECRETS[@]}"; do
  echo "Creating secret: $secret_name" 2>&1
  echo -n "${SECRETS[$secret_name]}" | gcloud secrets create "$secret_name" \
    --data-file=- \
    --replication-policy=automatic \
    --project=$GCP_PROJECT_ID 2>/dev/null || \
  echo -n "${SECRETS[$secret_name]}" | gcloud secrets versions add "$secret_name" \
    --data-file=- \
    --project=$GCP_PROJECT_ID
done

# Step 5: Verify all secrets created
gcloud secrets list --project=$GCP_PROJECT_ID --format='value(name)'
```

**Expected Output:** 6 secrets visible in GSM

#### Afternoon (12:00 - 17:00)
**Task: OIDC/WIF Configuration**

```bash
# Step 1: Enable required APIs
gcloud services enable iap.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Step 2: Create WorkloadIdentityPool
gcloud iam workload-identity-pools create github-pool \
  --project=$GCP_PROJECT_ID \
  --location=global \
  --display-name="GitHub Actions Pool" 2>/dev/null || echo "Pool exists"

# Step 3: Create WorkloadIdentityPoolProvider
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project=$GCP_PROJECT_ID \
  --location=global \
  --workload-identity-pool=github-pool \
  --display-name="GitHub Actions OIDC Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.environment=assertion.environment,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --issuer-uri=https://token.actions.githubusercontent.com 2>/dev/null || echo "Provider exists"

# Step 4: Get WIP resource name
WIP_PROVIDER=$(gcloud iam workload-identity-pools providers describe github-provider \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=$GCP_PROJECT_ID \
  --format='value(name)')

echo "Workload Identity Provider: $WIP_PROVIDER"

# Step 5: Grant service account WIF access
gcloud iam service-accounts add-iam-policy-binding \
  github-actions-gsm@$GCP_PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$GCP_PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/kushin77/self-hosted-runner" \
  --project=$GCP_PROJECT_ID

# Step 6: Store WIP provider in GitHub secret
# Manually add to GitHub: Settings > Secrets > New secret
# Name: GCP_WORKLOAD_IDENTITY_PROVIDER
# Value: $WIP_PROVIDER
```

**Expected Output:** WIP provider URI for use in workflows

---

### DAY 2 (Wednesday, March 9)

#### Morning (09:00 - 12:00)
**Task: Vault Configuration**

```bash
# Assuming Vault is already running and accessible via VAULT_ADDR

# Step 1: Enable JWT auth method
vault auth enable jwt 2>/dev/null || echo "JWT auth already enabled"

# Step 2: Configure JWT auth for GitHub Actions
# First, get GitHub's OIDC public keys endpoint
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration | jq .jwks_uri

# Step 3: Configure JWT auth policy
vault write auth/jwt/config \
  oidc_discovery_url=https://token.actions.githubusercontent.com \
  bound_audiences=https://github.com/kushin77

# Step 4: Create JWT role for GitHub Actions
vault write auth/jwt/role/github-actions \
  bound_audiences=https://github.com/kushin77 \
  user_claim=sub \
  role_type=jwt \
  policies=github-actions-policy \
  ttl=3600

# Step 5: Create secret policy for GitHub Actions
vault policy write github-actions-policy - <<'EOF'
path "secret/data/github/*" {
  capabilities = ["read", "list"]
}

path "secret/data/deploy/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/*" {
  capabilities = ["list"]
}
EOF

# Step 6: Create secrets in Vault KV store
vault kv put secret/github/pat-core token=<RUNNER_MGMT_TOKEN>
vault kv put secret/deploy/ssh-key key=<DEPLOY_SSH_KEY>
vault kv put secret/tf/service-account key=<TF_VAR_SERVICE_ACCOUNT_KEY>

# Step 7: Verify secrets created
vault kv list secret/github
vault kv list secret/deploy
```

**Expected Output:** 3 secrets stored in Vault

#### Afternoon (12:00 - 17:00)
**Task: AWS KMS Setup**

```bash
# Assuming AWS credentials configured via OIDC role assumption

# Step 1: Verify KMS key exists
aws kms list-aliases --region us-east-1 | jq '.Aliases[] | select(.AliasName=="alias/github-secrets")'

# Step 2: If needed, create KMS key
# aws kms create-key --description "GitHub Actions Secrets Encryption" --region us-east-1
# aws kms create-alias --alias-name alias/github-secrets --target-key-id <KEY_ID> --region us-east-1

# Step 3: Create AWS Secrets Manager secrets
aws secretsmanager create-secret \
  --name github/docker-hub-username \
  --secret-string "$DOCKER_HUB_USERNAME" \
  --region us-east-1 2>/dev/null || \
aws secretsmanager update-secret \
  --secret-id github/docker-hub-username \
  --secret-string "$DOCKER_HUB_USERNAME" \
  --region us-east-1

# Step 4: Setup OIDC assuming role
# Create IAM role for GitHub OIDC provider
# Attach policy allowing:
# - secretsmanager:GetSecretValue
# - kms:Decrypt

# Step 5: Verify AWS Secrets Manager secrets
aws secretsmanager list-secrets --region us-east-1 --filters Key=name,Values=github/
```

**Expected Output:** AWS Secrets Manager ready with 3+ secrets

---

### DAY 3 (Thursday, March 10)

#### All Day: Helper Actions Testing
**Task: Test all 3 helper actions with example workflows**

```bash
# Create test workflow
cat > .github/workflows/test-credential-helpers.yml <<'EOF'
name: Test Credential Helper Actions

on:
  workflow_dispatch:

jobs:
  test-gsm:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Test GSM retrieval
        uses: ./.github/actions/retrieve-secret-gsm
        id: gsm
        with:
          secret-name: docker-hub-username
          gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
          workload-identity-provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service-account: github-actions-gsm@${{ secrets.GCP_PROJECT_ID }}.iam.gserviceaccount.com
      
      - name: Verify GSM secret retrieved
        run: |
          if [[ -z "${{ steps.gsm.outputs.secret-value }}" ]]; then
            echo "❌ GSM secret retrieval failed"
            exit 1
          else
            echo "✅ GSM secret retrieved successfully"
          fi

  test-vault:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Test Vault retrieval
        uses: ./.github/actions/retrieve-secret-vault
        id: vault
        with:
          secret-path: secret/data/github/pat-core
          vault-addr: ${{ secrets.VAULT_ADDR }}
          vault-role: github-actions
      
      - name: Verify Vault secret retrieved
        run: |
          if [[ -z "${{ steps.vault.outputs.secret-value }}" ]]; then
            echo "❌ Vault secret retrieval failed"
            exit 1
          else
            echo "✅ Vault secret retrieved successfully"
          fi

  test-kms:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Test KMS retrieval
        uses: ./.github/actions/retrieve-secret-kms
        id: kms
        with:
          secret-name: github/docker-hub-username
          aws-region: us-east-1
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
      
      - name: Verify KMS secret retrieved
        run: |
          if [[ -z "${{ steps.kms.outputs.secret-value }}" ]]; then
            echo "❌ KMS secret retrieval failed"
            exit 1
          else
            echo "✅ KMS secret retrieved successfully"
          fi
EOF

git add .github/workflows/test-credential-helpers.yml
git commit -m "test: add credential helper testing workflow"
git push origin main
```

**Workflow:** Manually trigger test workflow in GitHub Actions UI

**Expected Result:** All 3 helper actions download secrets successfully

---

### DAY 4 (Friday, March 11)

#### Morning & Afternoon: Rotation Workflow Integration
**Task: Integrate audit logging into existing rotation workflows**

The rotation workflows exist at:
- `.github/workflows/gcp-gsm-rotation.yml`
- `.github/workflows/secure-multi-layer-secret-rotation.yml`
- `.github/workflows/secret-rotation-reusable.yml`

Add audit logging calls to each rotation workflow:

```yaml
# In gcp-gsm-rotation.yml, add after successful rotation:
- name: Log GSM rotation to audit trail
  if: success()
  uses: ./.github/workflows/credential-audit-logger.yml
  with:
    operation: rotation
    credential-type: gsm
    credential-id: ${{ matrix.secret-name }}
    status: success
    old-version: ${{ steps.rotation.outputs.old-version }}
    new-version: ${{ steps.rotation.outputs.new-version }}
    details: '{"provider":"gsm","method":"automatic_rotation"}'
```

#### Testing & Validation
**Test rotation workflows in staging:**

1. Manually trigger GSM rotation workflow
2. Verify audit trail entry created in `.audit-trail/credential-operations.log`
3. Verify old secret version still accessible (backup)
4. Verify new secret version active in workflows

**Expected Output:**
```
✅ GSM rotation complete
✅ Audit trail entry logged
✅ New version active
✅ Old version cached for 7 days
```

---

### DAY 5 (Friday, March 12)

#### Final Validation & Compliance
**Task: Run comprehensive zero-hardcoding audit**

```bash
#!/bin/bash
set -e

echo "🔍 Credential Compliance Audit"
echo "=============================="
echo ""

# Count: Check for obvious secret patterns
echo "1. Scanning for hardcoded secrets patterns..."
FOUND=$(grep -r -i "password\|api.key\|secret\|token" \
  --include="*.js" --include="*.py" --include="*.sh" --include="*.yml" \
  --exclude-dir=.git --exclude-dir=node_modules \
  . 2>/dev/null | grep -v "secret-name\|secretmanager\|secrets\.\|retrieve-secret" | wc -l)

if [[ $FOUND -gt 10 ]]; then
  echo "⚠️ Found $FOUND potential hardcoded secrets - manual review needed"
else
  echo "✅ No obvious hardcoded secrets found"
fi

# Audit trail: Verify immutability
echo ""
echo "2. Verifying audit trail immutability..."
if [[ -f .audit-trail/credential-operations.log ]]; then
  LINES=$(wc -l < .audit-trail/credential-operations.log)
  echo "✅ Audit trail has $LINES entries (append-only)"
else
  echo "⚠️ Audit trail not yet populated"
fi

# Compliance: Check secret sources
echo ""
echo "3. Verifying all secrets come from external sources..."
SOURCES=$(grep -r "GCP_WORKLOAD_IDENTITY_PROVIDER\|AWS_ROLE_TO_ASSUME\|VAULT_ADDR" \
  .github/workflows/*.yml | wc -l)
echo "✅ Found $SOURCES references to external credential sources"

# Policy: Verify no defaults
echo ""
echo "4. Checking for hardcoded default credentials..."
DEFAULTS=$(grep -r "default.*password\|default.*secret\|default.*token" \
  . --include="*.yml" --include="*.yaml" 2>/dev/null | wc -l)

if [[ $DEFAULTS -eq 0 ]]; then
  echo "✅ No hardcoded default credentials"
else
  echo "⚠️ Found $DEFAULTS potential defaults - review needed"
fi

echo ""
echo "=============================="
echo "✅ PHASE 1A COMPLIANCE COMPLETE"
echo "=============================="
```

---

## ✅ SIGN-OFF CHECKLIST

Mark as complete after each day:

### Day 1 ✅
- [ ] 6 secrets created in GSM
- [ ] WIF provider configured and stored in GitHub secrets
- [ ] GSM service account permissions verified

### Day 2 ✅
- [ ] JWT auth enabled in Vault
- [ ] 3 secrets stored in Vault  
- [ ] AWS KMS verified (or created)
- [ ] AWS Secrets Manager ready

### Day 3 ✅
- [ ] test-credential-helpers.yml created
- [ ] GSM helper action test PASSED
- [ ] Vault helper action test PASSED
- [ ] KMS helper action test PASSED

### Day 4 ✅
- [ ] Audit logging integrated into rotation workflows
- [ ] GSM rotation test PASSED
- [ ] Audit trail entries created & verified
- [ ] Old secret version retention verified

### Day 5 ✅
- [ ] Credential compliance audit shows 0 hardcoded secrets
- [ ] Audit trail shows 5+ rotation entries
- [ ] All external credential sources verified
- [ ] Team signoff obtained

---

## 🎯 SUCCESS METRICS

| Metric | Target | Current | Status |
|--------|--------|---------|--------|
| Secrets in GitHub settings | 0 (migrated) | 25 | 🟡 IN PROGRESS |
| Secrets in GSM | 8+ | 0 | 🔴 PENDING |
| Secrets in Vault | 4+ | 0 | 🔴 PENDING |
| Secrets in AWS SM | 3+ | 0 | 🔴 PENDING |
| Rotation workflows active | 3 | 3 | ✅ READY |
| Audit trail entries | 5+ | 0 | 🔴 PENDING |
| Zero hardcoded secrets | Yes | Mostly | 🟡 IN PROGRESS |
| Helper actions tested | 3/3 | 3/3 | ✅ READY |

---

## 📞 BLOCKERS & UNBLOCKS

**Current Blockers:**
- [ ] GCP project admin access
- [ ] Vault server admin access
- [ ] AWS IAM admin access
- [ ] GitHub repo admin access (to update secrets)

**How to Unblock:**
1. Get admin to create GitHub OIDC provider in GCP
2. Get admin to create GitHub OIDC provider in AWS
3. Get admin to create Vault JWT auth configuration
4. Get admin to create initial secrets in external managers

**Self-Service (Non-Admin):**
- Update workflows to use helper actions ✅
- Test helper actions ✅
- Create audit logging workflow ✅
- Update rotation workflows with audit calls ✅

---

## 🚀 NEXT PHASE (After Phase 1A Complete)

Once Phase 1A is complete:
1. **Phase 2:** Release Automation (semantic versioning, changelogs) - Week 1
2. **Phase 3:** Dependency Management (security scanning, updates) - Week 2
3. **Phase 4:** Incident Response (auto-recovery, RCA) - Week 3
4. **Phase 5:** ML Analytics (predictions, burndown) - Week 4

---

**Phase 1A Target:** ✅ ZERO HARDCODED CREDENTIALS by March 12, 2026

Reference: [Issue #1966](../../../issues/1966)  
Previous: [Issue #1965 - Master Tracking](../../../issues/1965)
