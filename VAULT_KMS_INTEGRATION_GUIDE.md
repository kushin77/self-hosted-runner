# VAULT + KMS CREDENTIAL MANAGEMENT SYSTEM
# Production-Grade Three-Layer Secret Rotation & Encryption

---

## 🎯 ARCHITECTURE OVERVIEW

### Three-Layer Credential Management

```
┌─────────────────────────────────────────────────────────┐
│  GitHub Actions (Event-Driven CI/CD)                    │
│  P1-P5 Deployment Automation Phases                     │
└───────────────────┬─────────────────────────────────────┘
                    │
      ┌─────────────┼─────────────┐
      │             │             │
      ▼             ▼             ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│   GSM    │  │ VAULT    │  │   KMS    │
├──────────┤  ├──────────┤  ├──────────┤
│ Primary  │  │ Dynamic  │  │ Encrypt  │
│ Secrets  │  │ Rotation │  │ at Rest  │
└──────────┘  └──────────┘  └──────────┘
      │             │             │
      └─────────────┼─────────────┘
                    │
      ┌─────────────▼─────────────┐
      │ Reconciliation & Audit    │
      │ (Every 6 hours)           │
      └───────────────────────────┘
```

### What Each System Does

| Layer | System | Purpose | Rotation | Encryption |
|-------|--------|---------|----------|-----------|
| **1** | GCP GSM | Primary secret storage | Hourly | At-rest |
| **2** | Vault  | Dynamic credential generation | Every 6h | In-transit |
| **3** | KMS    | Encryption key management | Every 6h | At-rest + key rotation |

---

## 🔐 IMMUTABILITY, EPHEMERALNESS, IDEMPOTENCY

### ✅ Immutable
- All credential configs in Git (Vault HCL)
- No manual credential modifications
- Terraform code defines infrastructure (credentials via interpolation)
- Audit trail through GitHub, Vault, CloudTrail

### ✅ Ephemeral
- **GCP GSM**: Credentials valid ~1 hour
- **Vault**: Dynamic credentials < 1 hour TTL
- **KMS**: Encryption keys rotate automatically
- No long-lived secrets in code or storage

### ✅ Idempotent
- Rotation workflow safe to run multiple times
- No race conditions (Vault handles distributed lock)
- KMS key rotation doesn't invalidate old material
- Same input → same output always

---

## 🚀 AUTOMATED CREDENTIAL ROTATION SCHEDULE

### Basic Schedule (Every 6 Hours)

```
00:00 UTC → Layer 1 (GSM) + Layer 2 (Vault) + Layer 3 (KMS)
06:00 UTC → Layer 1 + Layer 2 + Layer 3
12:00 UTC → Layer 1 + Layer 2 + Layer 3
18:00 UTC → Layer 1 + Layer 2 + Layer 3

Plus P5 drift detection every 30 minutes (non-destructive)
```

### Enhanced Schedule (Optional)

```
Hourly: P5 drift detection (read-only)
Every 6h: Full credential rotation (Vault + KMS)
Daily: GSM secrets audit
Weekly: Key rotation audit
Monthly: Full security audit
```

---

## 📋 CREDENTIAL LIFECYCLE

### When GitHub Actions Runs (P1-P5)

```
1. GitHub OIDC token issued
   ├─ Valid for: 5-15 minutes
   └─ Expected audience: sts.github.actions

2. Authenticate to each system:
   ├─ GCP → Workload Identity ($TIMESTAMP)
   ├─ AWS → AssumeRoleWithWebIdentity ($TIMESTAMP)
   └─ Vault → JWT auth ($TIMESTAMP)

3. Fetch ephemeral credentials:
   ├─ GCP: Service account token (< 1h)
   ├─ AWS: Session credentials (< 1h)
   └─ Vault: Dynamic credentials (< 1h)

4. Use credentials for terraform:
   ├─ Plan: Read-only (safe)
   ├─ Apply: Read-write (gated)
   └─ Destroy: Read-write (very gated)

5. Credentials expire after workflow:
   ├─ AWS sessions auto-revoke
   ├─ GCP tokens auto-expire
   └─ Vault leases auto-revoke
```

### Credential Rotation (Every 6 Hours)

```
1. Vault rotates dynamic credentials
   └─ Old: Revoked (< 5 min grace)
   └─ New: Generated & stored

2. KMS rotates key material
   └─ New master key generated
   └─ Old key kept for decryption (backwards compat)

3. GSM syncs to Vault
   └─ Latest credentials pushed
   └─ Audit logged

4. Reconciliation check
   └─ All 3 systems verified in sync
   └─ No conflicts or drift
```

---

## 🔧 OPERATOR SETUP (Phase-by-Phase)

### Phase 1: HashiCorp Vault Setup (1-2 hours)

#### Option A: Self-Hosted Vault

```bash
# 1. Install Vault (CentOS/Ubuntu)
wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
unzip vault_1.15.0_linux_amd64.zip
sudo mv vault /usr/local/bin/

# 2. Configure storage backend (Consul or Integrated Storage)
cat > /etc/vault/config.hcl <<'EOF'
ui = true
storage "file" {
  path = "/opt/vault/data"
}
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = false
  tls_cert_file = "/etc/vault/tls/vault.crt"
  tls_key_file  = "/etc/vault/tls/vault.key"
}
EOF

# 3. Start Vault
sudo systemctl start vault

# 4. Initialize & unseal
vault operator init -key-shares=5 -key-threshold=3
vault operator unseal <KEY1>
vault operator unseal <KEY2>
vault operator unseal <KEY3>

# 5. Login
vault login <ROOT_TOKEN>
```

#### Option B: HashiCorp Cloud Platform (Easiest)

```bash
# 1. Create account at https://cloud.hashicorp.com
# 2. Launch managed Vault cluster
# 3. Get VAULT_ADDR and auth method

export VAULT_ADDR="https://vault-cluster.vault.11eb.hcp.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"
```

#### Phase 1 Summary
- [ ] Vault cluster running (self-hosted or HCP)
- [ ] TLS certificates configured
- [ ] Initial unsealing complete
- [ ] VAULT_ADDR accessible from GitHub Actions

---

### Phase 2: Configure Vault for GitHub Actions (30-45 minutes)

```bash
export VAULT_ADDR="https://your-vault-address"
export VAULT_TOKEN="<root-token>"

# 1. Enable JWT auth method
vault auth enable jwt

# 2. Configure JWT for GitHub OIDC
vault write auth/jwt/config \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  oidc_client_id="sts.github.actions" \
  default_role="github-actions"

# 3. Create GitHub Actions role
vault write auth/jwt/role/github-actions \
  bound_audiences="sts.github.actions" \
  user_claim="actor" \
  role_type="jwt" \
  policies="github-actions" \
  ttl="1h" \
  max_ttl="1h"

# 4. Create policy for GitHub Actions
cat > /tmp/github-actions-policy.hcl <<'EOF'
# Dynamic AWS credentials
path "aws/creds/github-role" {
  capabilities = ["create", "read"]
}

# Dynamic GCP credentials
path "gcp/key/github-sa" {
  capabilities = ["create", "read"]
}

# Read terraform secrets
path "secret/data/terraform/*" {
  capabilities = ["read"]
}

# Lease renewal
path "sys/leases/renew" {
  capabilities = ["update"]
}
EOF

vault policy write github-actions /tmp/github-actions-policy.hcl

# 5. Configure AWS secret engine
vault secrets enable aws

vault write aws/config/root \
  access_key="AWS_KEY_ID" \
  secret_key="AWS_SECRET_KEY" \
  region="us-east-1"

vault write aws/roles/github-role \
  credential_type="assumed_role" \
  role_arns="arn:aws:iam::ACCOUNT_ID:role/vault-github-role" \
  ttl="1h" \
  max_ttl="6h"

# 6. Configure GCP secret engine
vault secrets enable gcp

vault write gcp/config \
  credentials=@/path/to/gcp-service-account.json \
  project_id="YOUR_GCP_PROJECT"

vault write gcp/roleset/github-sa \
  service_account="vault-github@YOUR_GCP_PROJECT.iam.gserviceaccount.com" \
  secret_type="service_account_key"

# 7. Enable KV secrets
vault secrets enable -version=2 -path=secret kv

# 8. Test connection
curl -H "Authorization: Bearer $JWT" \
  "$VAULT_ADDR/v1/auth/jwt/login" \
  -d '{"jwt":"<github-token>"}' \
  | jq '.auth.client_token'
```

---

### Phase 3: Configure AWS KMS (45 minutes)

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Create KMS master key
KMS_KEY=$(aws kms create-key \
  --description "GitHub Actions encryption key" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --query 'KeyMetadata.KeyId' --output text)

echo "KMS_KEY_ID=$KMS_KEY"

# 2. Enable automatic key rotation
aws kms enable-key-rotation --key-id "$KMS_KEY"

# 3. Create key policy for Vault
cat > /tmp/kms-key-policy.json <<'EOF'
{
  "Sid": "Enable Vault Use",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::ACCOUNT_ID:role/vault-github-role"
  },
  "Action": [
    "kms:Decrypt",
    "kms:GenerateDataKey",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}
EOF

aws kms put-key-policy --key-id "$KMS_KEY" --policy-name default --policy file:///tmp/kms-key-policy.json

# 4. Verify key is accessible
aws kms describe-key --key-id "$KMS_KEY"

# 5. Enable CloudTrail for audit
aws s3 mb s3://vault-cloudtrail-logs-$AWS_ACCOUNT_ID

aws cloudtrail create-trail --name vault-kms-trail --s3-bucket-name vault-cloudtrail-logs-$AWS_ACCOUNT_ID

aws cloudtrail start-logging --trail-name vault-kms-trail
```

---

### Phase 4: Add GitHub Secrets (15 minutes)

**Add to GitHub Settings → Secrets and variables → Actions**:

```bash
# Vault Configuration
VAULT_ADDR=https://your-vault-address
VAULT_NAMESPACE=admin
VAULT_JWT_AUDIENCE=sts.github.actions

# KMS Configuration
KMS_KEY_ID=arn:aws:kms:us-east-1:ACCOUNT_ID:key/KEY_ID
KMS_ENCRYPTION_ENABLED=true

# AWS for KMS access
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/github-terraform-oidc-role
AWS_SESSION_DURATION=3600

# GCP (if using dynamic credentials)
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/PROJECT_NUM/locations/global/workloadIdentityPools/github-pool/providers/github-provider
GCP_SERVICE_ACCOUNT_EMAIL=github-terraform-sa@PROJECT_ID.iam.gserviceaccount.com
GCP_PROJECT_ID=YOUR_GCP_PROJECT
```

Using GitHub CLI:

```bash
gh secret set VAULT_ADDR --body "https://vault-addr" --repo kushin77/self-hosted-runner
gh secret set VAULT_NAMESPACE --body "admin" --repo kushin77/self-hosted-runner
gh secret set KMS_KEY_ID --body "arn:aws:kms:..." --repo kushin77/self-hosted-runner
# ... (repeat for all secrets)
```

---

## ✅ VERIFICATION CHECKLIST

### Vault Setup
- [ ] Vault cluster running and accessible
- [ ] JWT auth method enabled
- [ ] GitHub Actions role created
- [ ] AWS secrets engine configured
- [ ] GCP secrets engine configured
- [ ] GitHub can authenticate to Vault

### KMS Setup
- [ ] KMS key created and enabled
- [ ] Auto-rotation enabled
- [ ] Key policy allows GitHub Actions
- [ ] CloudTrail logging active
- [ ] AWS credentials working

### GitHub Integration
- [ ] All secrets added to repository
- [ ] Vault + KMS rotation workflow enables
- [ ] First rotation cycle completes successfully
- [ ] No credential errors in Actions logs
- [ ] Credentials properly rotated in all 3 systems

---

## 🧪 TESTING THE SYSTEM

### Manual Rotation Test

```bash
# Trigger the workflow
gh workflow run vault-kms-credential-rotation.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f rotation_mode=full

# Watch execution
gh run view --repo kushin77/self-hosted-runner --log | tail -50
```

### Verify Credentials Were Rotated

```bash
# Check Vault
vault read secret/data/terraform/backend

vault read aws/creds/github-role

vault read gcp/key/github-sa

# Check KMS logs
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GenerateDataKey

# Check GSM
gcloud secrets versions list terraform-backend-config
```

---

## 📊 MONITORING & ALERTS

### Key Metrics to Monitor

```
1. Credential Rotation Success Rate
   - Target: 100%
   - Alert: If < 95%

2. KMS Key Rotation Status
   - Expected: Every 6 hours
   - Alert: If > 8 hours since last rotation

3. Vault Lease Expiration
   - Target: < 1 hour renewal before expiry
   - Alert: If lease expires without renewal

4. Vault Audit Logs
   - Expected: Auth success rate > 99%
   - Alert: If auth failures > 5 in 1 hour

5. CloudTrail KMS Events
   - Expected: Steady encryption/decryption
   - Alert: If abnormal pattern detected
```

### Automated Monitoring (Optional)

```bash
# Add to GitHub Actions for daily audit
- name: Check Credential Rotation Health
  run: |
    # Check last vault rotation timestamp
    LAST_ROTATION=$(vault read -field=last_rotation secret/metadata/terraform/backend)
    AGE=$(($(date +%s) - $(date -d "$LAST_ROTATION" +%s)))
    
    if [ $AGE -gt 28800 ]; then  # 8 hours
      echo "⚠️ Credentials not rotated in > 8 hours"
      exit 1
    fi
```

---

## 🎯 BENEFITS OF THIS THREE-LAYER SYSTEM

### Redundancy
- If one system fails, others provide fallback
- Attestation across independent systems
- No single point of failure

### Compliance
- Meets SOC2, CIS, NIST requirements
- Full audit trail across all 3 systems
- Encryption, rotation, access controls

### Security
- Multiple encryption at rest (GSM, KMS)
- Encryption in transit (Vault TLS)
- Ephemeral credentials everywhere
- Immutable infrastructure

### Scalability
- Vault handles unlimited credential types
- KMS scales to enterprise use
- GSM already handles thousands of secrets

---

## 📞 TROUBLESHOOTING

### Vault Auth Fails

```
Error: "Invalid JWT"

Solutions:
1. Verify OIDC discovery URL: https://token.actions.githubusercontent.com/.well-known/openid-configuration
2. Check role bound_audiences matches "sts.github.actions"
3. Verify JWT audience in GitHub token matches config
4. Check Vault logs: vault audit list
```

### KMS Encryption Fails

```
Error: "User is not authorized to perform KMS operations"

Solutions:
1. Verify role has KMS permissions
2. Check key policy allows the role
3. Verify KMS key exists and is enabled
4. Check AWS credentials are valid
```

### Credentials Not Rotating

```
Error: "Rotation workflow did not complete"

Solutions:
1. Check workflow trigger (schedule or manual)
2. Verify Vault cluster is healthy
3. Check KMS key is accessible
4. Review GitHub Actions logs for errors
5. Manually trigger: gh workflow run ...
```

---

## ✅ OPERATOR READINESS

Once setup complete:

- [x] GSM operational (already done)
- [x] Vault cluster running & accessible
- [x] KMS key created with auto-rotation
- [x] GitHub secrets configured
- [x] Rotation workflow tested
- [x] All 3 systems verified working
- [x] Monitoring alerts in place

**System Ready for**: Production-grade credential management with automatic rotation every 6 hours

---

*Three-layer credential management: GCP GSM (primary) ↔ HashiCorp Vault (dynamic) ↔ AWS KMS (encryption)*
