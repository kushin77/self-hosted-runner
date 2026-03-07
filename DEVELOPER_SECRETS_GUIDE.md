# Developer Guide: Working with Secrets

**Target Audience**: Developers, DevOps engineers, security team  
**Last Updated**: March 7, 2026  
**Companion Files**: [SECRETS_INDEX.md](SECRETS_INDEX.md), [SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)

---

## Overview

This guide explains how to find, use, and manage secrets programmatically in the self-hosted runner repository. Instead of hunting through documentation, developers can use command-line tools and scripts to discover what secrets exist and how to use them.

---

## Quick Start: Finding All Secrets

### Option 1: Human-Readable Summary

```bash
# See overview of secrets status
bash scripts/audit-secrets.sh

# Output example:
# 📊 SECRETS SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Total Secrets Found:        18
# Workflows Analyzed:         45
# Secrets Configured:         15
# Secrets Missing:            3
# ✅ All required secrets configured
```

### Option 2: Complete Details

```bash
# Full report with usage details
bash scripts/audit-secrets.sh --full

# Shows every secret + which workflows use it
```

### Option 3: Programmatic (JSON)

```bash
# Get structured data for integration
bash scripts/audit-secrets.sh --json > /tmp/secrets.json

# Parse with jq
jq '.secrets[] | select(.status=="MISSING")' /tmp/secrets.json
```

---

## Common Developer Tasks

### 1. Find Which Workflows Use a Secret

```bash
# Search for workflows using DEPLOY_SSH_KEY
grep -l "DEPLOY_SSH_KEY" .github/workflows/*.yml

# Output:
# .github/workflows/runner-self-heal.yml
# .github/workflows/deploy-rotation-staging.yml
```

### 2. Find All Secrets Used by a Workflow

```bash
# Extract secrets from a specific workflow
grep -o '\${{ secrets\.[A-Z_]*' .github/workflows/e2e-validate.yml | \
  sed 's/\${{ secrets\.//' | sort -u

# Output:
# GITHUB_TOKEN
# MINIO_ACCESS_KEY
# MINIO_BUCKET
# MINIO_ENDPOINT
# MINIO_SECRET_KEY
```

### 3. Search for Secrets by Pattern

```bash
# Find all GCP-related secrets
bash scripts/audit-secrets.sh --search "GCP_"

# Output:
#   • GCP_PROJECT_ID (used in 3 workflows)
#   • GCP_SERVICE_ACCOUNT_EMAIL (used in 2 workflows)
#   • GCP_WORKLOAD_IDENTITY_PROVIDER (used in 4 workflows)
```

### 4. Check Configuration Status

```bash
# Validate all required secrets exist
bash scripts/audit-secrets.sh --validate

# Shows:
# ✅ All required secrets configured
# or
# ❌ Missing required secrets: VAULT_ROLE_ID, VAULT_SECRET_ID
```

### 5. Show Only Missing Secrets

```bash
# Quick check: what's missing?
bash scripts/audit-secrets.sh --missing-only

# Output:
# Missing Secrets:
#   • SLACK_WEBHOOK_URL (scope: OPTIONAL)
#   • PAGERDUTY_TOKEN (scope: OPTIONAL)
```

---

## Adding a New Secret: Step-by-Step

### Step 1: Determine Storage Location

Choose where to store your secret based on lifetime and scope:

```
┌─────────────────────────────────────────────────────────┐
│ Secret Lifetime & Scope Decision Tree                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Used in multiple repos?                                │
│    YES → Use Google Secret Manager (GSM)                │
│    NO  → Use GitHub Secrets                             │
│                                                          │
│  Credential (AWS key, API key)?                         │
│    YES → Rotate every 90 days                           │
│    NO  → Rotate time-based (180-365 days)               │
│                                                          │
│  Requires dynamic rotation?                             │
│    YES → Use HashiCorp Vault (AppRole)                  │
│    NO  → Use static secret management                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Step 2: Create Secret in Storage

**Option A: GitHub Secrets (Repo Level)**

```bash
# Interactive prompt for value
gh secret set MY_NEW_SECRET --repo kushin77/self-hosted-runner

# Or pipe from file
gh secret set MY_NEW_SECRET --repo kushin77/self-hosted-runner < /path/to/secret.txt
```

**Option B: GCP Secret Manager**

```bash
# Authenticate to GCP first
gcloud auth login
gcloud config set project gcp-eiq

# Create new secret
echo "my-secret-value" | gcloud secrets create my-new-secret \
  --replication-policy=automatic \
  --data-file=-

# Or add version to existing
echo "new-value" | gcloud secrets versions add my-new-secret --data-file=-
```

**Option C: HashiCorp Vault**

```bash
# Authenticate to Vault
vault login -method=approle \
  -path=auth/approle \
  role_id="$VAULT_ROLE_ID" \
  secret_id="$VAULT_SECRET_ID"

# Write secret
vault kv put secret/myapp/database password="mypassword" user="myuser"
```

### Step 3: Use in Workflow

```yaml
name: My Workflow
on: [push]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Use new secret
        env:
          MY_NEW_SECRET: ${{ secrets.MY_NEW_SECRET }}  # GitHub Secret
          # OR for GSM:
          GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
        run: |
          # GitHub Secret (direct)
          echo "Using: $MY_NEW_SECRET"
          
          # GSM Secret (requires OIDC + gcloud)
          gcloud secrets versions access latest \
            --secret=my-new-secret \
            --project=$GCP_PROJECT_ID
```

### Step 4: Document the Secret

**Update [SECRETS_INDEX.md](SECRETS_INDEX.md):**

1. Add row to appropriate table (GitHub/GSM/Vault)
2. Include: name, type, purpose, rotation schedule
3. Link to workflows using it

**Example:**

```markdown
| `MY_NEW_SECRET` | API Key | Integration | 90 days | ✅ Yes | Authenticates to external service |
```

### Step 5: Add to Workflow

```yaml
- name: Check critical secrets for provisioning status
  id: secrets
  env:
    MY_NEW_SECRET: ${{ secrets.MY_NEW_SECRET }}
  run: |
    if [ -n "${MY_NEW_SECRET}" ]; then
      echo "my_secret_status=configured" >> $GITHUB_OUTPUT
    fi
```

### Step 6: Validate

```bash
# Run audit to verify it's recognized
bash scripts/audit-secrets.sh --validate

# Should show:
# ✅ MY_NEW_SECRET: Configured
```

### Step 7: Create Pull Request

```bash
git checkout -b feat/add-my-secret
# Make changes
git add SECRETS_INDEX.md .github/workflows/
git commit -m "feat: add MY_NEW_SECRET for service integration

- Added GH secret MY_NEW_SECRET
- Updated e2e-validate.yml to use new secret
- Documented in SECRETS_INDEX.md
- Rotation: 90 days"

git push origin feat/add-my-secret
# Create PR
```

---

## Secret Types & Rotation Schedules

### High-Security (Rotate Every 30-90 Days)

- **SSH Keys**: 90 days
- **API Keys**: 90 days
- **Database Passwords**: 30 days
- **OAuth Tokens**: 90 days
- **Vault Secret IDs**: 24h (auto-rotated)

### Medium-Security (Rotate Every 180 Days)

- **Service Account Keys**: 180 days
- **SMTP Credentials**: 180 days
- **MinIO Access Keys**: 180 days
- **Webhook Tokens**: 180 days

### Low-Security (Rotate Annually)

- **Project IDs**: 365 days (reference data)
- **OIDC Endpoints**: 365 days (reference data)
- **Configuration URLs**: 365 days (reference data)

---

## Programmatic Access Patterns

### Pattern 1: GitHub Secrets + Workflow

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      API_KEY: ${{ secrets.API_KEY }}
    steps:
      - run: curl -H "Authorization: Bearer $API_KEY" https://api.example.com
```

### Pattern 2: GSM + OIDC Token Exchange

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # For OIDC token
      
    steps:
      - uses: google-github-actions/auth@v1
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account_email: ${{ secrets.GCP_SERVICE_ACCOUNT_EMAIL }}
      
      - run: |
          gcloud secrets versions access latest --secret=my-secret
```

### Pattern 3: Vault AppRole Auth

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      VAULT_ADDR: https://vault.example.com
      VAULT_ROLE_ID: ${{ secrets.VAULT_ROLE_ID }}
      VAULT_SECRET_ID: ${{ secrets.VAULT_SECRET_ID }}
    steps:
      - run: |
          VAULT_TOKEN=$(vault write -field=client_token \
            auth/approle/login \
            role_id="$VAULT_ROLE_ID" \
            secret_id="$VAULT_SECRET_ID")
          vault kv get -field=password secret/database
```

### Pattern 4: MinIO/S3 Artifact Storage

```yaml
env:
  MINIO_ENDPOINT: ${{ secrets.MINIO_ENDPOINT }}
  MINIO_ACCESS_KEY: ${{ secrets.MINIO_ACCESS_KEY }}
  MINIO_SECRET_KEY: ${{ secrets.MINIO_SECRET_KEY }}

run: |
  # Upload artifact
  aws s3 cp artifact.tar.gz s3://${{ secrets.MINIO_BUCKET }}/artifacts/ \
    --endpoint-url="$MINIO_ENDPOINT"
```

---

## Validation Checklist

Before committing a secret to a workflow:

- [ ] Secret value is **never** hardcoded in YAML
- [ ] Secret is **not** printed/logged in run steps
- [ ] Secret has **minimum required permissions** (least privilege)
- [ ] Rotation schedule is **documented** in SECRETS_INDEX.md
- [ ] Secret is **encrypted in transit** (HTTPS/TLS)
- [ ] Secret is **encrypted at rest** (GitHub/GCP encryption)
- [ ] Access is **audit-logged** (GitHub/GCP/Vault)
- [ ] Documentation **links** workflows that use it
- [ ] OIDC used instead of **long-lived credentials** (when possible)
- [ ] Secret **scope** is limited (repo vs org vs global)

---

## Troubleshooting

### Secret Not Found in Workflow

```bash
# 1. Verify secret exists
gh secret list --repo kushin77/self-hosted-runner | grep SECRET_NAME

# 2. Check YAML syntax
grep -n "secrets\.SECRET_NAME" .github/workflows/my-workflow.yml

# 3. Verify secret is not in env: at top level
# ❌ WRONG:
# env:
#   MY_SECRET: ${{ secrets.MY_SECRET }}
# 
# ✅ RIGHT: 
# steps:
#   - name: Use secret
#     env:
#       MY_SECRET: ${{ secrets.MY_SECRET }}
```

### OIDC Token Exchange Fails

```bash
# 1. Validate OIDC provider setup
gcloud iam workload-identity-pools providers describe github \
  --location=global \
  --workload-identity-pool=github-actions \
  --project=gcp-eiq

# 2. Verify service account has correct role
gcloud iam service-accounts get-iam-policy \
  github-actions-terraform@gcp-eiq.iam.gserviceaccount.com

# 3. Check OIDC configuration in workflow
# Required: id-token: write permission + correct provider/account in auth action
```

### Secret Value Is Incorrect/Expired

```bash
# For GitHub Secrets
gh secret set MY_SECRET --repo kushin77/self-hosted-runner
# (interactive prompt - paste new value)

# For GSM
echo "new-value" | gcloud secrets versions add my-secret --data-file=-

# For Vault
vault kv put secret/path key=value
```

### Audit Script Shows Missing Secrets

```bash
# Check which are missing
bash scripts/audit-secrets.sh --missing-only

# For optional secrets, create if needed
gh secret set OPTIONAL_SECRET --repo kushin77/self-hosted-runner

# For required secrets, creation is mandatory - don't skip!
```

---

## Security Best Practices

### ✅ DO

- ✅ Rotate credentials every 30-90 days
- ✅ Use OIDC/WIF instead of static keys
- ✅ Log to audit trail (GitHub/GCP/Vault)
- ✅ Use strong unique values (avoid patterns)
- ✅ Limit secret scope (repo > org > global)
- ✅ Document rotation schedule
- ✅ Use `secrets.` syntax in workflows (encrypted at rest)
- ✅ Store backup recovery codes securely
- ✅ Review access logs regularly

### ❌ DON'T

- ❌ Commit secrets to git
- ❌ Hardcode values in YAML/scripts
- ❌ Share secrets in Slack/email/comments
- ❌ Use generic names like `PASSWORD` or `KEY`
- ❌ Create long-lived credentials without rotation
- ❌ Print secrets in logs (masked: `***` required)
- ❌ Store secrets in comments
- ❌ Reuse secrets across environments
- ❌ Leave rotating secrets unmanaged

---

## Tools & Integration

### IDE Support

**VS Code Secrets Highlighter** - Warns about potential secret leaks

```bash
# In .vscode/extensions.json
{
  "recommendations": [
    "GitHub.copilot",
    "trufflesecurity.trufflehog"  # Secret scanner
  ]
}
```

### Pre-commit Hook

Prevent accidental secret commits:

```bash
# Install detect-secrets
pip install detect-secrets

# Run scan
detect-secrets scan --baseline .secrets.baseline

# Update baseline after new secrets
detect-secrets scan --baseline .secrets.baseline --update-baseline
```

### CI/CD Integration

Automatically validate secrets in every PR:

```bash
# In your workflow
bash scripts/audit-secrets.sh --validate
```

---

## Related Documentation

- **[SECRETS_INDEX.md](SECRETS_INDEX.md)** ← Complete secrets inventory
- **[SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)** ← Setup instructions
- **[GSM_AWS_CREDENTIALS_QUICK_START.md](GSM_AWS_CREDENTIALS_QUICK_START.md)** ← AWS via GSM
- **[docs/VAULT_GETTING_STARTED.md](docs/VAULT_GETTING_STARTED.md)** ← Vault primer

---

## Questions?

1. **Find all secrets**: `bash scripts/audit-secrets.sh --full`
2. **Search for pattern**: `bash scripts/audit-secrets.sh --search "GCP_"`
3. **Read SECRETS_INDEX.md**: Complete reference with all secrets
4. **Check workflow YAML**: Look for `${{ secrets.` to see direct usage

---

*Last Updated: March 7, 2026*  
*Maintained by: Security & DevOps*  
*Next Review: June 7, 2026*
