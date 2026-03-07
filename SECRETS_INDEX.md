# Secrets Index & Catalog

**Last Updated**: March 7, 2026  
**Status**: 🔐 Complete Inventory  
**For Developers**: Use this to find, audit, and manage all secrets programmatically

---

## Quick Navigation

- [Search Secrets](#searching-secrets-programmatically) - How to find secret usage
- [All Secrets by Type](#all-secrets-by-type) - Complete inventory
- [Secrets by Solution Domain](#secrets-by-solution-domain) - Organized by purpose
- [Security Checklist](#security-checklist) - Before adding new secrets
- [Tools & Scripts](#tools--scripts) - Automation for secret discovery

---

## Searching Secrets Programmatically

### Option 1: Quick Shell Commands

```bash
# Find all GitHub secret references
grep -r "\${{ secrets\." .github/workflows/ | grep -oE 'secrets\.[A-Z_]+' | sort -u

# Find all GSM (Google Secret Manager) references  
grep -rE "gcloud secrets|GSM_|SECRET_[A-Z_]+" .github/workflows/ | grep -oE '\b[A-Z_]+' | sort -u

# Find all Vault references
grep -rE "VAULT_|vault" .github/workflows/ | grep -oE 'VAULT_[A-Z_]+' | sort -u

# Find all MinIO references
grep -r "MINIO_" .github/workflows/ | grep -oE 'MINIO_[A-Z_]+' | sort -u

# Show which workflows use a specific secret
grep -l "DEPLOY_SSH_KEY" .github/workflows/*.yml

# Generate HTML report of secret usage
bash scripts/audit-secrets.sh --html --output secret-audit.html
```

### Option 2: Use the Secrets Audit Script

```bash
# Full audit report (shows all secrets + workflows)
bash scripts/audit-secrets.sh --full

# JSON output for integration
bash scripts/audit-secrets.sh --json > secrets-manifest.json

# Search for specific secret
bash scripts/audit-secrets.sh --search "GCP_"

# Validate all required secrets are configured
bash scripts/audit-secrets.sh --validate

# Show only missing secrets
bash scripts/audit-secrets.sh --missing-only
```

---

## All Secrets by Type

### A. GitHub Secrets (Repository Level)

These are stored in GitHub Settings → Secrets and variables → Actions

| Secret Name | Type | Category | Rotation | Required | Purpose |
|-------------|------|----------|----------|----------|---------|
| **DEPLOY_SSH_KEY** | SSH Private Key (ED25519) | Infrastructure | 90 days | ✅ YES | Ansible SSH auth to runner hosts |
| **RUNNER_MGMT_TOKEN** | GitHub PAT | GitHub | 90 days | ✅ YES | Runner mgmt API, issue automation |
| **GCP_WORKLOAD_IDENTITY_PROVIDER** | Resource Path | GCP/OIDC | Never | ⭕ OPTIONAL | GitHub→GCP WIF (OIDC) endpoint |
| **GCP_SERVICE_ACCOUNT_EMAIL** | Email | GCP | Never | ⭕ OPTIONAL | GCP service account identifier |
| **GCP_PROJECT_ID** | Project ID | GCP | Never | ⭕ OPTIONAL | GCP project identifier |
| **GCP_SERVICE_ACCOUNT_KEY** | JSON | GCP | 90 days | ⭕ OPTIONAL | Direct GCP auth (if not using OIDC) |
| **GCP_WORKLOAD_IDENTITY_SERVICE_ACCOUNT** | Email | GCP/OIDC | Never | ⭕ OPTIONAL | OIDC-impersonated service account |
| **AWS_OIDC_ROLE_ARN** | ARN | AWS/OIDC | Never | ⭕ OPTIONAL | GitHub→AWS OIDC role for Terraform |
| **USE_OIDC** | Boolean | AWS/OIDC | Never | ⭕ OPTIONAL | Flag: enable Terraform OIDC auth |
| **MINIO_ENDPOINT** | URL | MinIO | Never | ⭕ OPTIONAL | MinIO S3 server endpoint |
| **MINIO_ACCESS_KEY** | API Key | MinIO | 180 days | ⭕ OPTIONAL | MinIO access credentials |
| **MINIO_SECRET_KEY** | API Secret | MinIO | 180 days | ⭕ OPTIONAL | MinIO secret credentials |
| **MINIO_BUCKET** | Bucket Name | MinIO | Never | ⭕ OPTIONAL | MinIO artifact bucket name |
| **SMTP_RELAY_URL** | URL | Email | 180 days | ⭕ OPTIONAL | SMTP relay for email notifications |
| **PAGERDUTY_TOKEN** | API Token | Alerting | 90 days | ⭕ OPTIONAL | PagerDuty incident creation |
| **COSIGN_PRIVATE_KEY** | Private Key | Signing | 365 days | ⭕ OPTIONAL | Cosign artifact signing key |
| **VAULT_ROLE_ID** | UUID | Vault | Never | ⭕ OPTIONAL | Vault AppRole role ID |
| **VAULT_SECRET_ID** | UUID | Vault | 90 days | ⭕ OPTIONAL | Vault AppRole secret ID |

**Set GitHub Secrets:**
```bash
# List all configured secrets
gh secret list --repo kushin77/self-hosted-runner

# Set a secret interactively
gh secret set SECRET_NAME --repo kushin77/self-hosted-runner

# Delete a secret
gh secret delete SECRET_NAME --repo kushin77/self-hosted-runner
```

---

### B. GCP Secret Manager Secrets

These are stored in Google Cloud Secret Manager (GSM) and accessed via OIDC

| Secret Name | Type | GSM Project | Scope | Rotation | Purpose |
|-------------|------|-------------|-------|----------|---------|
| **terraform-aws-prod** | AWS Access Key | gcp-eiq | AWS Creds | 90 days | AWS_ACCESS_KEY_ID for Terraform |
| **terraform-aws-secret** | AWS Secret Key | gcp-eiq | AWS Creds | 90 days | AWS_SECRET_ACCESS_KEY for Terraform |
| **terraform-aws-region** | AWS Region | gcp-eiq | AWS Creds | Never | AWS_REGION for Terraform (us-east-1) |
| **slack-webhook-url** | Webhook URL | gcp-eiq | Notifications | 180 days | Slack channel notifications |
| **smtp-relay-url** | SMTP URL | gcp-eiq | Email | 180 days | SMTP relay endpoint |

**Access GSM Secrets:**
```bash
# List all secrets in gcp-eiq project
gcloud secrets list --project=gcp-eiq

# Retrieve a secret value
gcloud secrets versions access latest --secret=terraform-aws-prod --project=gcp-eiq

# Add new version to existing secret
echo "new-value" | gcloud secrets versions add terraform-aws-prod --data-file=- --project=gcp-eiq

# Create new secret
echo "secret-value" | gcloud secrets create my-new-secret --replication-policy=automatic --data-file=- --project=gcp-eiq
```

---

### C. Vault Secrets (AppRole Auth)

These are stored in HashiCorp Vault and accessed via AppRole authentication

| Secret Path | Type | Engine | TTL | Purpose |
|-------------|------|--------|-----|---------|
| `auth/approle/role/github-actions/role-id` | Role ID | AppRole | N/A | Vault AppRole authentication |
| `auth/approle/role/github-actions/secret-id` | Secret ID | AppRole | 24h | Vault AppRole authentication |
| `secret/data/terraform/aws/*` | Dynamic | KV v2 | 1h | AWS credentials (if using Vault) |

**Access Vault Secrets:**
```bash
# Authenticate with AppRole
VAULT_TOKEN=$(vault write -field=client_token auth/approle/login \
  role_id="$VAULT_ROLE_ID" \
  secret_id="$VAULT_SECRET_ID")

# Retrieve secret
vault kv get -field=value secret/terraform/aws/access_key
```

---

## Secrets by Solution Domain

### Infrastructure & Deployment

**Purpose**: Ansible, Terraform, infrastructure automation

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `DEPLOY_SSH_KEY` | GitHub | `runner-self-heal.yml`, `deploy-rotation-staging.yml` | SSH auth to runner hosts for Ansible |
| `RUNNER_MGMT_TOKEN` | GitHub | `runner-self-heal.yml`, issue automation | GitHub API for runner status updates |
| `AWS_OIDC_ROLE_ARN` | GitHub | `terraform-apply.yml`, `terraform-plan.yml` | AWS access for Terraform (OIDC) |
| `terraform-aws-prod` | GSM | `elasticache-apply-gsm.yml` | AWS Access Key for Terraform |
| `terraform-aws-secret` | GSM | `elasticache-apply-gsm.yml` | AWS Secret Key for Terraform |

**Workflows:**
- [.github/workflows/runner-self-heal.yml](.github/workflows/runner-self-heal.yml) - Uses DEPLOY_SSH_KEY, RUNNER_MGMT_TOKEN
- [.github/workflows/terraform-apply.yml](.github/workflows/terraform-apply.yml) - Uses AWS_OIDC_ROLE_ARN (OIDC)
- [.github/workflows/elasticache-apply-gsm.yml](.github/workflows/elasticache-apply-gsm.yml) - Uses GSM AWS credentials

---

### Cloud Integration (GCP)

**Purpose**: GCP authentication, Secret Manager access, workload identity

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GitHub | `gcp-permission-validator.yml`, any GCP workflow | OIDC provider endpoint |
| `GCP_SERVICE_ACCOUNT_EMAIL` | GitHub | `gcp-permission-validator.yml`, `store-slack-to-gsm.yml` | Service account identifier |
| `GCP_PROJECT_ID` | GitHub | Multiple workflows | GCP project identifier |
| `GCP_SERVICE_ACCOUNT_KEY` | GitHub | `store-slack-to-gsm.yml` | Direct auth (fallback to OIDC) |

**Workflows:**
- [.github/workflows/gcp-permission-validator.yml](.github/workflows/gcp-permission-validator.yml) - Validates GCP setup
- [.github/workflows/store-slack-to-gsm.yml](.github/workflows/store-slack-to-gsm.yml) - Stores notifications in GSM

---

### Artifact Storage (MinIO)

**Purpose**: S3-compatible artifact storage for CI/CD

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `MINIO_ENDPOINT` | GitHub | `e2e-validate.yml`, artifact workflows | MinIO server URL |
| `MINIO_ACCESS_KEY` | GitHub | `e2e-validate.yml`, artifact workflows | MinIO API access |
| `MINIO_SECRET_KEY` | GitHub | `e2e-validate.yml`, artifact workflows | MinIO API secret |
| `MINIO_BUCKET` | GitHub | `e2e-validate.yml`, artifact workflows | Bucket name |

**Workflows:**
- [.github/workflows/e2e-validate.yml](.github/workflows/e2e-validate.yml) - Uses MinIO for artifact storage

**Scripts:**
- `scripts/minio/upload.sh` - Upload to MinIO
- `scripts/minio/download.sh` - Download from MinIO

---

### Notifications & Alerting

**Purpose**: Slack, email, PagerDuty integrations

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `SMTP_RELAY_URL` | GitHub | `store-slack-to-gsm.yml` | Email notifications |
| `slack-webhook-url` | GSM | `store-slack-to-gsm.yml` | Slack channel messages |
| `PAGERDUTY_TOKEN` | GitHub | Incident workflows | Create/manage PagerDuty incidents |

**Workflows:**
- [.github/workflows/store-slack-to-gsm.yml](.github/workflows/store-slack-to-gsm.yml) - Notification integration

---

### Signing & Verification

**Purpose**: Artifact signing, release verification

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `COSIGN_PRIVATE_KEY` | GitHub | `slsa-provenance-release.yml` | Sign container images/artifacts |

**Workflows:**
- [.github/workflows/slsa-provenance-release.yml](.github/workflows/slsa-provenance-release.yml) - Image signing

---

### Hashicorp Vault

**Purpose**: Centralized secrets management with dynamic credentials

| Secret | Storage | Workflow | Usage |
|--------|---------|----------|-------|
| `VAULT_ROLE_ID` | GitHub | Vault auth workflows | AppRole role identifier |
| `VAULT_SECRET_ID` | GitHub | Vault auth workflows | AppRole secret (rotated 24h) |

**Documentation:**
- [docs/VAULT_GETTING_STARTED.md](docs/VAULT_GETTING_STARTED.md) - Complete Vault setup guide

---

## Security Checklist

Before adding a new secret to the repository, verify:

- [ ] **Never commit secrets** to git (use `.gitignore` with `*secret*`, `*key*`, `*.pem`)
- [ ] **Use GitHub Secrets** by default for repo-level authentication
- [ ] **Use GSM** for shared, rotated credentials across multiple repos
- [ ] **Use OIDC** instead of long-lived credentials when possible
- [ ] **Rotation schedule** defined (90 days max for credentials)
- [ ] **Least privilege**: secret has minimum required permissions
- [ ] **Audit logging** enabled (GitHub, GCP, AWS CloudTrail)
- [ ] **Documented** with secret name, purpose, rotation schedule
- [ ] **Access control** limited to specific workflows/jobs
- [ ] **Encrypted in transit** (HTTPS, TLS 1.3 minimum)
- [ ] **Encrypted at rest** (GitHub/GCP encryption enabled)

---

## Tools & Scripts

### 1. Secrets Audit Script

**Location**: `scripts/audit-secrets.sh`

Automatically discovers and reports all secrets used across workflows.

```bash
# Run complete audit
bash scripts/audit-secrets.sh --full

# JSON output for programmatic access
bash scripts/audit-secrets.sh --json

# Validate secrets are configured
bash scripts/audit-secrets.sh --validate

# Search for specific pattern
bash scripts/audit-secrets.sh --search "GCP_"

# Generate HTML report
bash scripts/audit-secrets.sh --html --output report.html
```

**Output Includes:**
- All secret references across workflows
- Which jobs/steps use each secret
- Missing required secrets
- Compliance with rotation policies
- Security recommendations

---

### 2. Secrets Validator Script

**Location**: `scripts/validate-secrets.sh`

Validates that all required secrets are properly configured.

```bash
bash scripts/validate-secrets.sh
```

**Checks:**
- ✅ All GitHub secrets set
- ✅ All GSM secrets accessible
- ✅ All secret values are non-empty
- ✅ OIDC configuration correct (if enabled)
- ✅ Permissions correct for service accounts

---

### 3. Secrets Rotation Assistant

**Location**: `scripts/rotate-secrets.sh`

Helps safely rotate credentials on schedule.

```bash
# Rotate all 90-day credentials
bash scripts/rotate-secrets.sh --rotate-90d

# Rotate specific secret
bash scripts/rotate-secrets.sh --rotate DEPLOY_SSH_KEY

# Show rotation schedule
bash scripts/rotate-secrets.sh --schedule
```

---

### 4. IDE Integration (VS Code)

Add to `.vscode/extensions.json`:

```json
{
  "recommendations": [
    "GitHub.copilot",
    "ms-vscode.makefile-tools",
    "redhat.vscode-yaml",
    "ms-azuretools.vscode-docker"
  ]
}
```

**For Secret Discovery in Editor:**
1. Install "Secrets Highlighter" extension
2. Press `Cmd+K Cmd+S` to open keyboard shortcuts
3. Search for "find secret" to discover secret usage

---

## Developer Workflow

### Adding a New Secret

1. **Determine Storage Location**
   ```
   Short-lived (< 1 month)          → GitHub Secret
   Long-lived (> 1 month)           → GitHub Secret (w/ 90d rotation policy)
   Shared across repos             → GSM (Google Secret Manager)
   Requires dynamic rotation        → HashiCorp Vault
   ```

2. **Check Security Requirements**
   - Review [Security Checklist](#security-checklist) above
   - Run `bash scripts/audit-secrets.sh --validate`

3. **Create the Secret**
   ```bash
   # GitHub Secret
   gh secret set MY_NEW_SECRET --repo kushin77/self-hosted-runner
   
   # GSM Secret
   echo "secret-value" | gcloud secrets create my-new-secret \
     --replication-policy=automatic --data-file=- --project=gcp-eiq
   ```

4. **Document the Secret**
   - Add entry to this file (SECRETS_INDEX.md)
   - Include: name, type, purpose, rotation schedule
   - Link to workflows that use it

5. **Update Workflows**
   ```yaml
   - name: Use new secret
     env:
       MY_NEW_SECRET: ${{ secrets.MY_NEW_SECRET }}
     run: echo "Using $MY_NEW_SECRET"
   ```

6. **Validate**
   ```bash
   bash scripts/audit-secrets.sh --validate
   ```

7. **Create PR** with documentation updates

---

## Workflows Using Secrets

### High-Usage Workflows (> 5 secrets)

1. **[.github/workflows/e2e-validate.yml](.github/workflows/e2e-validate.yml)**
   - MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET
   - GITHUB_TOKEN

2. **[.github/workflows/gcp-permission-validator.yml](.github/workflows/gcp-permission-validator.yml)**
   - GCP_SERVICE_ACCOUNT_EMAIL, GCP_PROJECT_ID
   - GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_WORKLOAD_IDENTITY_SERVICE_ACCOUNT
   - GITHUB_TOKEN

3. **[.github/workflows/store-slack-to-gsm.yml](.github/workflows/store-slack-to-gsm.yml)**
   - GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT_EMAIL
   - GCP_PROJECT_ID, GCP_SERVICE_ACCOUNT_KEY
   - GITHUB_TOKEN

---

## Troubleshooting

### Secret Not Found in Workflow

```bash
# Verify secret is configured
gh secret list --repo kushin77/self-hosted-runner | grep SECRET_NAME

# Check if secret is used in any workflows
grep -r "SECRET_NAME" .github/workflows/

# Validate the secret value is not empty
gh secret list --repo kushin77/self-hosted-runner
```

### OIDC Token Exchange Failing

```bash
# Validate OIDC provider setup
gcloud iam workload-identity-pools providers describe github \
  --location=global \
  --workload-identity-pool=github-actions \
  --project=gcp-eiq

# Check service account OIDC permissions
gcloud iam service-accounts get-iam-policy github-actions-terraform@gcp-eiq.iam.gserviceaccount.com
```

### GSM Secret Access Denied

```bash
# Verify service account has Secret Manager role
gcloud projects get-iam-policy gcp-eiq \
  --flatten="bindings[].members" \
  --filter="bindings.members:github-actions-terraform@gcp-eiq.iam.gserviceaccount.com"

# Expected role: roles/secretmanager.secretAccessor
```

---

## Quick Reference Commands

```bash
# List all GitHub secrets
gh secret list --repo kushin77/self-hosted-runner

# List all GSM secrets
gcloud secrets list --project=gcp-eiq

# Find secret usage in workflows  
grep -r '\${{ secrets\.' .github/workflows/ | grep -oE 'secrets\.[A-Z_]+' | sort -u

# Audit all secrets (full report)
bash scripts/audit-secrets.sh --full

# Validate secrets configuration
bash scripts/audit-secrets.sh --validate

# Check for hardcoded secrets (security scan)
cd .github/workflows && detect-secrets scan --baseline .secrets.baseline

# Generate JSON manifest
bash scripts/audit-secrets.sh --json > secrets-manifest.json
```

---

## Related Documentation

- **[SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)** - Step-by-step setup instructions
- **[SECRETS_COMPLETE_DELIVERY.md](SECRETS_COMPLETE_DELIVERY.md)** - Implementation summary
- **[GSM_AWS_CREDENTIALS_QUICK_START.md](GSM_AWS_CREDENTIALS_QUICK_START.md)** - AWS credentials via GSM
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Adding new features (includes secret guidelines)
- **[docs/VAULT_GETTING_STARTED.md](docs/VAULT_GETTING_STARTED.md)** - Vault integration guide

---

## Support

**Questions about secrets?**

1. Check this index first (SECRETS_INDEX.md)
2. Run `bash scripts/audit-secrets.sh --search "keyword"`
3. Review the relevant workflow file in `.github/workflows/`
4. See [Troubleshooting](#troubleshooting) section above
5. Open issue with label `secrets` for clarification

**Need to add a new secret?**

Follow [Developer Workflow](#developer-workflow) → Adding a New Secret section above.

---

*Last Audit: March 7, 2026*  
*Maintained by: Security & DevOps Team*  
*Next Review: June 7, 2026*
