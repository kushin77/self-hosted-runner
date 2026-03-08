# 🚀 Phase 2: OIDC/WIF Configuration - EXECUTE NOW

**Status:** Ready for immediate execution

**Issue:** #1947

---

## ✅ INSTANT EXECUTION (Copy & Paste)

Open your terminal and run ONE of these commands:

### Option A: Full Auto-Detection (Recommended)
```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run setup-oidc-infrastructure.yml \
  -f gcp_project_id="$(gcloud config get-value project 2>/dev/null || echo 'YOUR-GCP-PROJECT')" \
  -f aws_account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo '123456789012')" \
  -f vault_address="${VAULT_ADDR:-https://vault.example.com:8200}" \
  -f vault_namespace="" \
  --ref main
```

### Option B: Manual Input
```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run setup-oidc-infrastructure.yml \
  -f gcp_project_id="YOUR-GCP-PROJECT-ID" \
  -f aws_account_id="YOUR-AWS-ACCOUNT-ID" \
  -f vault_address="https://vault.example.com:8200" \
  -f vault_namespace="" \
  --ref main
```

### Option C: Minimal (Uses environment defaults)
```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run setup-oidc-infrastructure.yml --ref main
```

---

## 📊 What Executes

When you run the above, Phase 2 workflow will:

**Step 1: GCP Workload Identity Federation**
- ✓ Create WIF pool for GitHub Actions
- ✓ Create WIF provider for your repository  
- ✓ Create service account with permissions
- ✓ Configure WIF bindings
- ✓ Output: `WIF_PROVIDER_ID`

**Step 2: AWS OIDC Provider**
- ✓ Create OIDC provider (github.com)
- ✓ Create IAM role for GitHub Actions
- ✓ Attach required policies
- ✓ Output: `AWS_ROLE_ARN`

**Step 3: Vault JWT Authentication**
- ✓ Enable JWT auth method
- ✓ Configure GitHub OIDC endpoint
- ✓ Create JWT role for workflows
- ✓ Create JWT policy for credentials
- ✓ Output: Configuration verification

**Step 4: GitHub Secrets**
- ✓ Create `GCP_WIF_PROVIDER_ID`
- ✓ Create `AWS_ROLE_ARN`
- ✓ Create `VAULT_ADDR`
- ✓ Create `VAULT_JWT_ROLE`

---

## ⏱️ Timeline

- **Duration:** 3-5 minutes
- **Start Time:** Now (when you copy/paste command)
- **End Time:** ~5 minutes later
- **No Manual Steps:** Fully automated

---

## 🎯 After Execution

### 1. Monitor Workflow
```bash
# Option A: View in browser
open "https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml"

# Option B: Check via CLI
gh run list --workflow=setup-oidc-infrastructure.yml -L 1
```

### 2. Verify Success (Look for green checkmark)
- Workflow shows "completed" status
- All steps show green checkmarks
- No error messages

### 3. Download Artifacts
```bash
# Get run ID
RUN_ID=$(gh run list --workflow=setup-oidc-infrastructure.yml --limit=1 --json databaseId -q '.[0].databaseId')

# Download artifacts
gh run download $RUN_ID -D /tmp/phase2-artifacts/
```

### 4. Verify Secrets Created
```bash
gh secret list --repo kushin77/self-hosted-runner
# Should show:
# GCP_WIF_PROVIDER_ID
# AWS_ROLE_ARN
# VAULT_ADDR
# VAULT_JWT_ROLE
```

### 5. Close Issue #1947
```bash
gh issue edit 1947 --state closed \
  --body "✅ Phase 2 Complete: OIDC/WIF infrastructure configured and tested

Workflow: setup-oidc-infrastructure.yml
Status: SUCCESS
Duration: ~5 minutes

Infrastructure Components:
✓ GCP Workload Identity Federation pool & provider
✓ AWS OIDC provider & GitHub role
✓ Vault JWT authentication
✓ GitHub repository secrets configured

Next: Phase 3 - Key Revocation"
```

---

## 🔍 Expected Logs

When workflow runs, you should see messages like:

```
✓ Verifying GCP project configuration
✓ Creating WIF pool: github-actions-pool
✓ Creating WIF provider: github-provider
✓ Creating service account: gha-workload-sa
✓ Binding WIF to service account
✓ Testing WIF authentication

✓ Creating AWS OIDC provider
✓ Creating GitHub role: GitHubActionsRole
✓ Attaching required policies
✓ Creating trust relationship

✓ Enabling Vault JWT auth
✓ Configuring JWT auth method
✓ Creating JWT role: github-actions
✓ Creating JWT policy: github-actions-policy

✓ Creating GitHub repository secrets
✓ GCP_WIF_PROVIDER_ID created
✓ AWS_ROLE_ARN created
✓ VAULT_ADDR created
✓ VAULT_JWT_ROLE created

✅ Phase 2 Complete: All infrastructure configured
```

---

## 🆘 Troubleshooting

**Command doesn't work:**
- Ensure you're in `/home/akushnir/self-hosted-runner` directory
- Run `gh auth status` to verify GitHub CLI is authenticated
- Check you have write access to repository

**GCP step fails:**
- Verify GCP project ID is correct
- Ensure you have "Project Editor" or higher IAM role
- Check gcloud is configured: `gcloud config list`

**AWS step fails:**
- Verify AWS account ID is correct  
- Ensure IAM permissions to create OIDC providers
- Check AWS CLI is configured: `aws sts get-caller-identity`

**Vault step fails:**
- Verify Vault address is accessible
- Ensure Vault authentication token is valid
- Check Vault is unsealed and available

**Workflow won't trigger:**
- Try Option C (minimal command)
- Run: `gh workflow run setup-oidc-infrastructure.yml --ref main`
- Check for any workflow file issues

---

## 📋 Success Criteria

Phase 2 is complete when:

- [x] Workflow execution shows green checkmark
- [x] All 4 steps completed successfully  
- [x] 4 GitHub secrets created (GCP_WIF_PROVIDER_ID, AWS_ROLE_ARN, VAULT_ADDR, VAULT_JWT_ROLE)
- [x] No errors in workflow logs
- [x] Artifacts downloadable
- [x] Issue #1947 closed

---

## 🔄 Next Phase

After Phase 2 completes:

**Execute Phase 3: Key Revocation**
```bash
# See PHASE_3_EXECUTION_GUIDE.md
```

---

## ✨ Current Status

```
Phase 1: ✅ COMPLETE (deployed)
Phase 2: 🔴 READY (awaiting your command below)
Phase 3: ⏳ QUEUED
Phase 4: ⏳ QUEUED  
Phase 5: ⏳ QUEUED
```

---

## 🎯 YOUR ACTION REQUIRED

**Run this command now:**

```bash
cd /home/akushnir/self-hosted-runner && \
gh workflow run setup-oidc-infrastructure.yml \
  -f gcp_project_id="$(gcloud config get-value project 2>/dev/null || echo 'YOUR-GCP-PROJECT')" \
  -f aws_account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo '123456789012')" \
  -f vault_address="${VAULT_ADDR:-https://vault.example.com:8200}" \
  -f vault_namespace="" \
  --ref main
```

Then monitor at:
https://github.com/kushin77/self-hosted-runner/actions/workflows/setup-oidc-infrastructure.yml

---

**Ready? Copy the command above and paste into your terminal. ✨**
