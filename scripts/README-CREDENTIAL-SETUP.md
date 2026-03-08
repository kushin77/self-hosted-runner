# 🔐 Phase 1A: Credential Infrastructure Setup Scripts

**Purpose:** Automated setup for GCP Workload Identity Federation, AWS OIDC, and Vault JWT authentication.

**Status:** ✅ Ready to execute (Phase 1A - This Week)

---

## 📋 Quick Start

### Option 1: Run All Three (Recommended)
```bash
cd scripts
./setup-credential-infrastructure.sh
```

This orchestrates all three setup scripts with proper sequencing and consolidated output.

### Option 2: Run Individual Scripts

```bash
# GCP Workload Identity Federation
./scripts/setup-gcp-wif.sh

# AWS OIDC Provider
./scripts/setup-aws-oidc.sh

# Vault JWT Auth
./scripts/setup-vault-jwt.sh
```

---

## 📖 Detailed Documentation

### GCP Workload Identity Federation Setup
**File:** `setup-gcp-wif.sh`

**What it does:**
- Enables required Google Cloud APIs (IAM, Secret Manager, etc.)
- Creates a service account for GitHub Actions
- Creates a Workload Identity Pool
- Creates an OIDC provider for GitHub
- Configures trust relationships
- Outputs WIP_PROVIDER URI for GitHub secrets

**Requirements:**
- `gcloud` CLI installed and authenticated
- GCP project with billing enabled
- Proper IAM permissions

**Usage:**
```bash
export GCP_PROJECT_ID=your-project-id
./scripts/setup-gcp-wif.sh
```

**Environment Variables:**
- `GCP_PROJECT_ID` - Your GCP project ID (required if not set in shell)
- `GCP_REGION` - Region for resources (default: global)
- `GITHUB_REPO` - Repository in format owner/repo (default: kushin77/self-hosted-runner)
- `SERVICE_ACCOUNT_ID` - Service account name (default: github-actions-gsm)
- `OUTPUT_FILE` - Where to save credentials (default: /tmp/gcp-wif-credentials.txt)

**Output:**
```
GCP_PROJECT_ID=your-project
GCP_SERVICE_ACCOUNT_EMAIL=github-actions-gsm@your-project.iam.gserviceaccount.com
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider
```

**Time:** ~30 minutes

---

### AWS OIDC Provider Setup
**File:** `setup-aws-oidc.sh`

**What it does:**
- Creates AWS OIDC provider for GitHub Actions
- Creates IAM role with assume role policy
- Attaches policies for Secrets Manager and KMS access
- Creates KMS encryption key
- Creates example AWS Secrets Manager secret
- Outputs role ARN for GitHub secrets

**Requirements:**
- `aws` CLI installed and configured
- AWS IAM permissions (CreateOpenIDConnectProvider, CreateRole, etc.)
- AWS account access

**Usage:**
```bash
export AWS_REGION=us-east-1
./scripts/setup-aws-oidc.sh
```

**Environment Variables:**
- `AWS_REGION` - AWS region (default: us-east-1)
- `AWS_ACCOUNT_ID` - AWS account ID (auto-detected if not set)
- `GITHUB_REPO` - Repository in format owner/repo (default: kushin77/self-hosted-runner)
- `ROLE_NAME` - IAM role name (default: github-actions-runner)
- `OUTPUT_FILE` - Where to save credentials (default: /tmp/aws-oidc-credentials.txt)

**Output:**
```
AWS_ROLE_TO_ASSUME=arn:aws:iam::123456789:role/github-actions-runner
AWS_OIDC_PROVIDER_ARN=arn:aws:iam::123456789:oidc-provider/token.actions.githubusercontent.com
AWS_KMS_KEY_ID=12345678-1234-1234-1234-123456789012
```

**Time:** ~30 minutes

---

### Vault JWT Auth Setup
**File:** `setup-vault-jwt.sh`

**What it does:**
- Enables JWT auth method in Vault
- Configures OIDC discovery for GitHub
- Creates JWT role for GitHub Actions
- Creates secret policy with appropriate permissions
- Creates sample secrets in Vault KV store
- Verifies entire configuration

**Requirements:**
- Vault server running and accessible
- VAULT_ADDR environment variable set
- VAULT_TOKEN with admin access
- `curl` and `jq` utilities installed

**Usage:**
```bash
export VAULT_ADDR=https://vault.example.com:8200
export VAULT_TOKEN=s.xxxxxxxxxxxxxxxx
./scripts/setup-vault-jwt.sh
```

**Environment Variables:**
- `VAULT_ADDR` - Vault server URL (required if not set interactively)
- `VAULT_TOKEN` - Vault auth token with admin access (required if not set interactively)
- `VAULT_NAMESPACE` - Vault namespace (optional)
- `GITHUB_REPO` - Repository in format owner/repo (default: kushin77/self-hosted-runner)
- `JWT_ROLE_NAME` - Vault JWT role name (default: github-actions)
- `OUTPUT_FILE` - Where to save credentials (default: /tmp/vault-jwt-credentials.txt)

**Output:**
```
VAULT_ADDR=https://vault.example.com:8200
VAULT_NAMESPACE=my-namespace (if using)
```

**Time:** ~20 minutes

---

## 🚀 Running the Complete Setup

### Recommended Approach

```bash
# 1. Before you start, prepare these environment variables:
export GCP_PROJECT_ID=your-gcp-project
export AWS_REGION=us-east-1
export VAULT_ADDR=https://vault.example.com:8200
export GITHUB_REPO=kushin77/self-hosted-runner

# 2. Run the master orchestration script:
cd /home/akushnir/self-hosted-runner
./scripts/setup-credential-infrastructure.sh

# 3. Follow the prompts:
#    - Confirm each setup (GCP, AWS, Vault)
#    - Provide credentials when requested
#    - Review final output

# 4. The script will create a consolidated credentials file:
cat /tmp/credential-infrastructure-setup.txt

# 5. Create GitHub secrets with the provided commands:
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/..."
gh secret set GCP_PROJECT_ID --body "your-project"
gh secret set GCP_SERVICE_ACCOUNT_EMAIL --body "github-actions-gsm@..."
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::..."
gh secret set VAULT_ADDR --body "https://vault.example.com:8200"
```

### Skip Individual Setups (if already done)

```bash
# Skip GCP setup:
./scripts/setup-credential-infrastructure.sh --skip-gcp

# Skip AWS setup:
./scripts/setup-credential-infrastructure.sh --skip-aws

# Skip Vault setup:
./scripts/setup-credential-infrastructure.sh --skip-vault

# Skip multiple:
./scripts/setup-credential-infrastructure.sh --skip-gcp --skip-aws
```

---

## ✅ Verification Checklist

After running all scripts, verify each setup:

### Verify GCP Setup
```bash
export GCP_PROJECT_ID=your-project-id

# List workload identity pools
gcloud iam workload-identity-pools list --location global

# List workload identity pool providers
gcloud iam workload-identity-pools providers list \
  --workload-identity-pool=github-pool \
  --location=global

# Check service account permissions
gcloud iam service-accounts get-iam-policy \
  github-actions-gsm@${GCP_PROJECT_ID}.iam.gserviceaccount.com

# List secrets in GSM
gcloud secrets list
```

### Verify AWS Setup
```bash
# List OIDC providers
aws iam list-open-id-connect-providers

# Check IAM role
aws iam get-role --role-name github-actions-runner

# Check role trust relationship
aws iam get-role --role-name github-actions-runner | jq '.Role.AssumeRolePolicyDocument'

# List KMS keys
aws kms list-aliases | grep github-secrets

# List Secrets Manager secrets
aws secretsmanager list-secrets
```

### Verify Vault Setup
```bash
# Using vault CLI:
vault auth list  # Should show jwt/

vault read auth/jwt/config

vault read auth/jwt/role/github-actions

vault policy read github-actions-policy

vault kv list secret/github

vault kv list secret/deploy
```

---

## 📊 Expected Output Files

After running the setup, you'll have these credential files:

```
/tmp/gcp-wif-credentials.txt          # GCP configuration
/tmp/aws-oidc-credentials.txt         # AWS configuration
/tmp/vault-jwt-credentials.txt        # Vault configuration
/tmp/credential-infrastructure-setup.txt  # Consolidated (from master script)
```

Each file contains:
- Configuration details
- GitHub secrets to create
- Usage examples for workflows
- Verification commands
- Troubleshooting tips

---

## 🔗 Integration with GitHub Actions

Once setup is complete, use these patterns in your workflows:

### GCP Secret Manager
```yaml
- uses: google-github-actions/auth@v1
  with:
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account_email: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}

- uses: ./.github/actions/retrieve-secret-gsm
  id: gsm
  with:
    secret-name: docker-hub-password
    gcp-project-id: ${{ secrets.GCP_PROJECT_ID }}
    workload-identity-provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service-account: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}

- run: echo "${{ steps.gsm.outputs.secret-value }}"
```

### AWS Secrets Manager
```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
    aws-region: us-east-1

- uses: ./.github/actions/retrieve-secret-kms
  id: aws
  with:
    secret-name: github/docker-hub-password
    role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}

- run: echo "${{ steps.aws.outputs.secret-value }}"
```

### Vault
```yaml
- uses: ./.github/actions/retrieve-secret-vault
  id: vault
  with:
    secret-path: secret/data/github/pat-core
    vault-addr: ${{ secrets.VAULT_ADDR }}
    vault-role: github-actions

- run: echo "${{ steps.vault.outputs.secret-value }}"
```

---

## 🛑 Troubleshooting

### GCP: "gcloud: command not found"
```bash
# Install Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### AWS: "An error occurred (AccessDenied)"
```bash
# Ensure you have correct IAM permissions:
# - iam:CreateOpenIDConnectProvider
# - iam:CreateRole
# - iam:PutRolePolicy
# - kms:CreateKey
# - kms:CreateAlias
# - secretsmanager:CreateSecret
```

### Vault: "curl: (35) OpenSSL SSL_connect: SSL_CERTIFICATE_VERIFY_FAILED"
```bash
# If using self-signed cert:
export VAULT_SKIP_VERIFY=true
# OR provide certificate:
export VAULT_CACERT=/path/to/ca.crt
```

### "Cannot connect to Vault"
```bash
# Check Vault server is running and accessible:
curl -k https://vault.example.com:8200/v1/sys/health

# Check firewall/network access
telnet vault.example.com 8200
```

---

## 📞 Next Steps

1. **Run Setup:** Execute `setup-credential-infrastructure.sh`
2. **Create Secrets:** Add output values to GitHub repository secrets
3. **Test Helpers:** Run `test-credential-helpers.yml` workflow
4. **Migrate Secrets:** Follow Phase 1A Execution Guide
5. **Verify Zero-Hardcoding:** Run compliance audit

---

## 📚 Related Documentation

- [Phase 1A Execution Guide](../docs/PHASE_1A_EXECUTION_GUIDE.md)
- [Credential Inventory](../docs/CREDENTIAL_INVENTORY.md)
- [Phase 1A Delivery Summary](../PHASE_1A_DELIVERY_SUMMARY.md)

---

**Scripts Created:** March 8, 2026  
**Phase:** 1A - Credential Management  
**Status:** ✅ Ready to Execute
