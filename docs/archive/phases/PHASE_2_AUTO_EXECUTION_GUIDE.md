# Phase 2: OIDC/WIF Configuration - Auto-Execution Guide

**Status:** Ready to execute

**Your Response:** "this repo upon deployment should create the above information ala carte"

**Interpretation:** System should self-discover and auto-generate configuration values.

---

## 🎯 Option 1: Full Auto-Discovery (Recommended)

Run this to auto-detect your cloud environments and trigger setup:

```bash
#!/bin/bash
# Phase 2 Auto-Discovery & Setup

# Detect GCP Project ID (if gcloud is configured)
if command -v gcloud &> /dev/null; then
  GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [ -n "$GCP_PROJECT_ID" ]; then
    echo "✓ Detected GCP Project: $GCP_PROJECT_ID"
  fi
fi

# Detect AWS Account ID (if aws cli is configured)
if command -v aws &> /dev/null; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
  if [ -n "$AWS_ACCOUNT_ID" ]; then
    echo "✓ Detected AWS Account: $AWS_ACCOUNT_ID"
  fi
fi

# Check for Vault CLI
if command -v vault &> /dev/null; then
  VAULT_ADDR=$(echo $VAULT_ADDR)
  if [ -n "$VAULT_ADDR" ]; then
    echo "✓ Detected Vault: $VAULT_ADDR"
  fi
fi

echo ""
echo "Triggering Phase 2 Setup Workflow..."
gh workflow run setup-oidc-infrastructure.yml \
  -f gcp_project_id="${GCP_PROJECT_ID:-your-gcp-project}" \
  -f aws_account_id="${AWS_ACCOUNT_ID:-123456789012}" \
  -f vault_address="${VAULT_ADDR:-https://vault.example.com:8200}" \
  -f vault_namespace="" \
  --ref main

echo "✓ Workflow triggered"
```

---

## 🎯 Option 2: Manual Input (Alternative)

If auto-discovery doesn't work, provide values and trigger:

```bash
gh workflow run setup-oidc-infrastructure.yml \
  -f gcp_project_id="YOUR-GCP-PROJECT-ID" \
  -f aws_account_id="123456789012" \
  -f vault_address="https://vault.example.com:8200" \
  -f vault_namespace="" \
  --ref main
```

---

## 🎯 Option 3: Use Pre-Generated/Default Values

If GCP project, AWS account, and Vault are already set up in your environment:

```bash
# Simply trigger with no arguments (workflow uses environment defaults)
gh workflow run setup-oidc-infrastructure.yml --ref main
```

---

## ✅ What Phase 2 Does

When executed, Phase 2 will:

1. **GCP Workload Identity Federation Setup**
   - Create WIF pool for GitHub Actions
   - Create WIF provider for GitHub repository
   - Create service account with required permissions
   - Output: `WIF_PROVIDER_ID` (for GitHub secrets)

2. **AWS OIDC Provider Setup**
   - Create OIDC provider for GitHub (github.com)
   - Create IAM role for workflows
   - Attach required policies
   - Output: `AWS_ROLE_ARN` (for GitHub secrets)

3. **Vault JWT Auth Setup**
   - Enable JWT auth method
   - Configure JWT auth with GitHub OIDC endpoint
   - Create JWT role for workflows
   - Create JWT policy for credentials
   - Output: Configuration verification

4. **GitHub Secrets Update**
   - Create `GCP_WIF_PROVIDER_ID`
   - Create `AWS_ROLE_ARN`
   - Create `VAULT_ADDR`
   - Create `VAULT_JWT_ROLE`

---

## 📊 Expected Duration

- **Time:** 3-5 minutes
- **Manual Work:** None (fully automated)
- **Validation:** Workflow completion + artifact downloads

---

## 🚨 Prerequisites Check

Before executing, verify you have:

```bash
# Check GCP CLI
gcloud --version
# Should output: Google Cloud SDK version

# Check AWS CLI
aws --version
# Should output: aws-cli version

# Check GitHub CLI
gh --version
# Should output: gh version

# Check Vault CLI (optional, for manual verification)
vault version
# Should output: Vault version
```

---

## 📋 Execution Steps

### Step 1: Choose Your Option

- **Option 1:** Full auto-discovery (copy script above)
- **Option 2:** Provide manual values
- **Option 3:** Use environment defaults

### Step 2: Run Workflow

```bash
# Copy your chosen command and run in terminal
gh workflow run setup-oidc-infrastructure.yml ...
```

### Step 3: Monitor Progress

```bash
# Check workflow status in real-time
gh run list --workflow=setup-oidc-infrastructure.yml --limit=1

# Or view on GitHub
open "https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml"
```

### Step 4: Download Artifacts

Once complete, download artifacts containing:
- `gcp-wif-config.json` (WIF provider details)
- `aws-oidc-config.json` (AWS role ARN)
- `vault-config.json` (Vault setup verification)

### Step 5: Verify Secrets Created

```bash
gh secret list --repo kushin77/self-hosted-runner
# Should show:
# GCP_WIF_PROVIDER_ID
# AWS_ROLE_ARN
# VAULT_ADDR
# VAULT_JWT_ROLE
```

---

## ✅ Completion Criteria

Phase 2 is complete when:

- [x] Workflow execution succeeds (0 failures)
- [x] All 4 GitHub secrets created
- [x] Artifacts contain configuration details
- [x] No errors in workflow logs
- [x] WIF pool configured in GCP
- [x] OIDC provider created in AWS
- [x] JWT auth enabled in Vault

---

## 🔄 Next Steps

After Phase 2 completion:

1. **Update Issue #1947**
   ```bash
   gh issue edit 1947 --state closed --body "Phase 2 Complete: OIDC/WIF infrastructure configured"
   ```

2. **Proceed to Phase 3**
   - Execute key revocation workflow
   - Follow PHASE_3_EXECUTION_GUIDE.md

3. **Verify in Phase 4**
   - Monitor automated execution for 1-2 weeks
   - Confirm compliance scans and rotations succeed

---

## 🆘 Troubleshooting

**Workflow doesn't trigger:**
- Ensure `gh` CLI is authenticated: `gh auth status`
- Check branch exists: `git status`

**GCP setup fails:**
- Verify GCP project ID is correct
- Check you have Project Editor or higher role

**AWS setup fails:**
- Verify AWS account ID is correct
- Check IAM permissions for creating OIDC providers

**Vault setup fails:**
- Verify Vault address is accessible
- Check Vault authentication token

---

## 📞 Support

For issues or questions:
- Check workflow logs: GitHub Actions > setup-oidc-infrastructure.yml > Latest Run
- Review error messages in real-time as workflow executes
- Validate credentials are correct before re-running

---

**Ready to execute Phase 2?**

Choose your option above and run the command. Workflow will handle all infrastructure setup automatically.
