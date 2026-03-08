# Phase 2: OIDC/WIF Auto-Discovery Infrastructure Setup - ACTIVATION GUIDE

**Status:** 🚀 READY FOR IMMEDIATE EXECUTION  
**Created:** 2026-03-08  
**Phase:** 2 of 5  
**Duration Estimate:** 10-30 minutes (fully automated)  
**All Previous Phases:** ✅ COMPLETE  

---

## 🎯 What Is Phase 2 Doing?

Phase 2 **eliminates all long-lived credentials** and replaces them with **OIDC/WIF (short-lived JWT tokens)**. This is a zero-trust architecture upgrade.

### Before Phase 2
```
GitHub Secrets (long-lived) 
    ↓
[RISK] If exposed → Full account compromise
    ↓
Manual credential rotation
```

### After Phase 2
```
GitHub OIDC → JWT Token (5-60 min lifetime) 
    ↓
GCP/AWS/Vault (validate JWT signature)
    ↓
[SAFE] JWT expires automatically; full account still secure
    ↓
Zero manual secrets storage
```

---

## 🚀 Phase 2 Execution (Quick Start)

### Option 1: Fully Automated (RECOMMENDED - 0 Manual Work)

```bash
# Just run this. System auto-detects everything.
gh workflow run phase-2-setup-oidc-auto-discovery.yml --ref main
```

**That's it.** Workflow will:
1. ✅ Auto-discover GCP Project ID
2. ✅ Auto-discover AWS Account ID  
3. ✅ Auto-discover Vault address
4. ✅ Configure all 3 providers (idempotent)
5. ✅ Generate provider IDs in artifacts
6. ✅ Produce completion guide

**Time:** ~15 minutes ⏱️

---

### Option 2: GitHub UI (If Terminal Not Available)

```
1. Go to: GitHub repo → Actions tab
2. Find: "Phase 2 - Setup OIDC Infrastructure (Auto-Discovery)"
3. Click: "Run workflow" button
4. Leave inputs BLANK (auto-discovery will fill them)
5. Click: Green "Run workflow" button
6. Wait: ~15 minutes for completion
7. Download: Artifacts with provider IDs
```

---

### Option 3: Hybrid (Auto-Discovery + Manual Overrides)

If auto-discovery can't find something:

```bash
gh workflow run phase-2-setup-oidc-auto-discovery.yml \
  --ref main \
  -f gcp-project-id=my-project-123 \
  -f aws-account-id=123456789012 \
  -f vault-addr=https://vault.example.com
```

The workflow will:
- Use your manual input for missing/overridden values
- Auto-discover the rest
- Proceed with merged credentials

---

## 📊 What Gets Auto-Discovered

### GCP Project ID
The workflow looks for it in (in order):
1. `gcloud config get-value project` (if authenticated)
2. `GOOGLE_APPLICATION_CREDENTIALS` (service account JSON)
3. `GCP_PROJECT_ID` environment variable
4. Manual input (if provided)

### AWS Account ID
The workflow looks for it in (in order):
1. `aws sts get-caller-identity` (if authenticated)
2. `AWS_ACCOUNT_ID` environment variable
3. IAM role ARN parsing (if available)
4. Manual input (if provided)

### Vault Address
The workflow looks for it in (in order):
1. `VAULT_ADDR` environment variable
2. GitHub Actions secret `VAULT_ADDR_FROM_SECRET`
3. `vault status` (if CLI available)
4. Manual input (if provided)

---

## ✅ What Happens During Phase 2

### Step 1: Credential Discovery (2 minutes)
- System scans for all credentials
- Creates discovery report (in artifacts)
- Displays what was found

### Step 2: Credential Validation (1 minute)
- Validates discovered + manual credentials
- Checks for required fields
- Fails early if anything is missing (safe)

### Step 3: GCP WIF Setup (5 minutes)
**Creates:**
- Workload Identity Federation (WIF) pool
- WIF provider (GitHub endpoint)
- Service account with WIF bindings
- Auto-generates provider ID for use in GitHub Actions

**Is Idempotent:** ✅ Yes - can run 1000x, same result

### Step 4: AWS OIDC Setup (5 minutes)
**Creates:**
- OIDC Provider (GitHub endpoint: `token.actions.githubusercontent.com`)
- IAM Role with GitHub assume-role policy
- Trust relationship (GitHub OIDC → AWS role)
- Auto-generates role ARN for GitHub Actions

**Is Idempotent:** ✅ Yes - can run 1000x, same result

### Step 5: Vault JWT Setup (5 minutes)
**Creates:**
- JWT auth method in Vault
- Role binding (GitHub claims → Vault policy)
- Auto-generates role name for use in workflows

**Is Idempotent:** ✅ Yes - can run 1000x, same result

### Step 6: Consolidation & Report (2 minutes)
- Downloads all setup logs
- Consolidates provider IDs
- Generates completion guide
- Creates `PHASE_2_COMPLETION.md` in artifacts

**Total Time:** 10-30 minutes (mostly waiting for cloud APIs)

---

## 📥 After Workflow Completes

### Step 1: Download Artifacts (2 minutes)

In GitHub Actions UI:
1. Find your workflow run
2. Scroll down to "Artifacts" section
3. Download: `setup-consolidated-<RUN_ID>`

This contains:
- `PHASE_2_COMPLETION.md` (guide with next steps)
- `setup-providers.json` (all provider IDs)
- `setup-all.log` (detailed logs from each provider)

### Step 2: Extract 6 Provider IDs (2 minutes)

From the `setup-providers.json` file, you'll get:

```json
{
  "gcp_workload_identity_provider": "projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider",
  "gcp_service_account": "github-oidc@my-project.iam.gserviceaccount.com",
  "aws_role_arn": "arn:aws:iam::123456789012:role/github-oidc-role",
  "vault_addr": "https://vault.example.com",
  "vault_namespace": "root",
  "vault_auth_role": "github-oidc"
}
```

### Step 3: Add 6 GitHub Repository Secrets (5 minutes)

In your GitHub repository:

```
Settings → Secrets and variables → Actions → New repository secret
```

Create these 6 secrets:

| Secret Name | Value From | Example |
|---|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | setup-providers.json | `projects/123.../providers/github-provider` |
| `GCP_SERVICE_ACCOUNT` | setup-providers.json | `github-oidc@project.iam.gserviceaccount.com` |
| `AWS_ROLE_ARN` | setup-providers.json | `arn:aws:iam::123456789012:role/github-oidc-role` |
| `VAULT_ADDR` | setup-providers.json | `https://vault.example.com` |
| `VAULT_NAMESPACE` | setup-providers.json | `root` (or your namespace) |
| `VAULT_AUTH_ROLE` | setup-providers.json | `github-oidc` |

**Important:** These are **NOT secrets** (they're public identifiers). The real security is in the OIDC trust relationships.

### Step 4: Verify OIDC Works (5 minutes)

Run a test:

```bash
# Trigger rotation workflow (uses OIDC internally)
gh workflow run rotation_schedule.yml --ref main

# Watch it complete
gh run list --limit 1 --workflow rotation_schedule.yml --status in_progress
```

If workflow succeeds: ✅ OIDC is working

---

## 🔒 Security Status After Phase 2

| Layer | Before | After | Status |
|---|---|---|---|
| **GCP** | Long-lived service account keys | OIDC JWT (5-60 min) | ✅ Upgraded |
| **AWS** | Long-lived AWS credentials | OIDC JWT (5-60 min) | ✅ Upgraded |
| **Vault** | AppRole/password auth | JWT auth (any TTL) | ✅ Upgraded |
| **Key Storage** | GitHub secrets | Cloud providers (immutable) | ✅ Upgraded |
| **Rotation** | Manual | Automated (daily) | ✅ Upgraded |
| **Audit Trail** | Partial | Complete immutable logs | ✅ Upgraded |

---

## ❌ Troubleshooting Auto-Discovery

### Problem: GCP Project ID Not Found

**Cause:** gcloud not authenticated or configured

**Solution:**
```bash
# Option 1: Set environment variable
gh workflow run phase-2-setup-oidc-auto-discovery.yml \
  --ref main \
  -f gcp-project-id=YOUR_PROJECT_ID

# Option 2: Authenticate gcloud
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Option 3: Check Application Credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
```

### Problem: AWS Account ID Not Found

**Cause:** AWS credentials not available

**Solution:**
```bash
# Option 1: Provide manually
gh workflow run phase-2-setup-oidc-auto-discovery.yml \
  --ref main \
  -f aws-account-id=123456789012

# Option 2: Configure AWS credentials
aws configured
# or
export AWS_PROFILE=myprofile
```

### Problem: Vault Address Not Found

**Cause:** Vault not installed or not configured

**Solution:**
```bash
# Option 1: Set environment variable
export VAULT_ADDR=https://vault.example.com

# Option 2: Provide in workflow
gh workflow run phase-2-setup-oidc-auto-discovery.yml \
  --ref main \
  -f vault-addr=https://vault.example.com
```

### Problem: Workflow Failed on GCP WIF Step

**Cause:** Missing GCP credentials or permission

**Solution:**
```bash
# Check that you have GCP credentials configured
gcloud auth list
gcloud config list

# Authenticate if needed
gcloud auth login
gcloud config set project MY_PROJECT

# Try workflow again
gh workflow run phase-2-setup-oidc-auto-discovery.yml --ref main
```

---

## 📚 Reference Documents

- **Issue #1947** — Phase 2 tracking (this phase)
- **SELF_HEALING_EXECUTION_CHECKLIST.md** — Phase 2 section with detailed steps
- **DEPLOYMENT_GUIDE.md** — Provider-specific OIDC/WIF configuration details
- **workflow file:** `.github/workflows/phase-2-setup-oidc-auto-discovery.yml`
- **discovery script:** `.github/scripts/discover-cloud-credentials.sh`

---

## 🔄 After Phase 2 Complete

### What's Working Now
✅ GCP: OIDC/WIF configured, zero long-lived keys  
✅ AWS: OIDC provider configured, zero long-lived credentials  
✅ Vault: JWT auth configured, zero shared secrets  
✅ GitHub: 6 provider IDs in repository secrets  
✅ Workflows: Can use OIDC/WIF for authentication (immutable)  

### What's Next: Phase 3 (Issue #1950)
- Revoke any exposed/compromised keys
- Verify all credential layers are healthy
- Run revoke-compromised-keys.yml workflow

### Timeline for Remaining Phases
- **Phase 2:** 10-30 min (THIS - auto-discovery)
- **Phase 3:** 1-2 hours (key revocation)
- **Phase 4:** 1-2 weeks (production validation)
- **Phase 5:** Ongoing (24/7 operations)

---

## 🎓 Key Concepts

### What is OIDC?
**OpenID Connect** - GitHub generates a signed JWT token, cloud provider verifies the signature. No secrets needed.

### What is WIF?
**Workload Identity Federation** - GCP-native way to use OIDC tokens for authentication (works with any OIDC provider).

### Why Is This Better?
- **Before:** Long-lived secrets → exposure = compromise
- **After:** JWT tokens (5-60 min lifetime) → exposure = limited impact

### Is This Production Ready?
✅ **YES** - This is used by every major tech company (Google, AWS, Azure, Meta, etc.)

---

## ✅ Execution Checklist

- [ ] Read this document completely
- [ ] Choose execution method (CLI or GitHub UI)
- [ ] Run Phase 2 workflow
- [ ] Wait for completion (~15 minutes)
- [ ] Download artifacts
- [ ] Extract 6 provider IDs
- [ ] Add 6 secrets to GitHub Actions
- [ ] Verify OIDC works (run rotation workflow)
- [ ] Proceed to Phase 3 (Issue #1950)

---

## 🚀 EXECUTE NOW

```bash
# Run this single command to start Phase 2
gh workflow run phase-2-setup-oidc-auto-discovery.yml --ref main

# Monitor progress (optional)
gh run list --limit 5 --workflow phase-2-setup-oidc-auto-discovery.yml

# Or go to GitHub UI → Actions tab to watch live
```

**No waiting. Auto-discovery handles the rest.**

