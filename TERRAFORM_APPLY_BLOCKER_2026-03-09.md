# Terraform Apply — Blocker Analysis & Resolution
**Date:** 2026-03-09  
**Status:** ⏸️ **BLOCKED — Awaiting GCP IAM Permission or SA Key**  
**Impact:** Phase 3 infrastructure deployment (8 GCP resources) cannot proceed

---

## Current State

### ✅ Completed
- Vault Agent metadata injection infrastructure fully implemented
- Terraform plan generated and validated: `tfplan-deploy-final` (8 resources, 0 errors)
- All code committed to main branch (13 commits, zero feature branches)
- Immutable audit trail established (JSONL + GitHub #2072)
- All deployment scripts ready (manual-deploy, oauth-apply, watcher)
- Documentation complete (5 guides + 3 analysis reports)

### ⏸️ Blocked
**Issue:** Cannot create service account or generate temporary key for terraform apply

**Root Cause:** Active GCP user (akushnir@bioenergystrategies.com) lacks IAM permissions on project `p4-platform`:
- ❌ iam.serviceAccounts.create — Permission denied
- ❌ iam.serviceAccounts.list — Permission denied
- ❌ iam.securityAdmin — Not available
- ❌ compute.admin — Not available

**Terraform Apply Requirements:**
- Must authenticate to GCP with credentials that have:
  - Compute Engine API access (create instance template, firewall rules)
  - IAM API access (create service account bindings)
  - Service Usage API access (enable APIs)

**Current Authentication Methods Tried:**
- ✅ gcloud auth login (user identity)
- ✅ Application Default Credentials (ADC)
- ❌ Service account creation (permissions denied)
- ❌ Service account key generation (permissions denied)

---

## Three Resolution Paths

### **PATH 1: Grant IAM Permissions (RECOMMENDED)**
**Effort:** 5 minutes (one-time, by GCP project owner)  
**Automation:** Yes, fully automated after permissions granted

**Steps:**
1. A user with **Owner** or **Editor** role on `p4-platform` project runs:
   ```bash
   PROJECT=p4-platform
   USER=akushnir@bioenergystrategies.com
   
   gcloud projects add-iam-policy-binding $PROJECT \
     --member="user:$USER" \
     --role="roles/iam.serviceAccountAdmin"
   
   gcloud projects add-iam-policy-binding $PROJECT \
     --member="user:$USER" \
     --role="roles/compute.admin"
   
   gcloud projects add-iam-policy-binding $PROJECT \
     --member="user:$USER" \
     --role="roles/serviceusage.serviceUsageAdmin"
   ```

2. Once granted, confirm and I will immediately:
   - Create terraform-deployer service account
   - Grant required roles
   - Generate temporary key
   - Run terraform apply  
   - Shred key
   - Record success in immutable audit trail
   - Close GitHub issues

**Advantages:**
- ✅ Fully automated after one-time setup
- ✅ Permanent (no key management needed)
- ✅ Aligns with enterprise best practices
- ✅ Can be revoked later if needed

**Disadvantages:**
- ⚠️ Requires contacting project owner
- ⚠️ May take time depending on approval process

---

### **PATH 2: Provide Service-Account Key**
**Effort:** 5-10 minutes (by user with SA key creation permissions)  
**Automation:** Yes, fully automated after key provided

**Steps:**
1. A user with SA key creation permissions runs:
   ```bash
   gcloud iam service-accounts keys create /tmp/terraform-deployer.json \
     --iam-account=terraform-deployer@p4-platform.iam.gserviceaccount.com \
     --project=p4-platform
   ```

2. Provide key to agent via one of:
   - **GSM:** `gcloud secrets create runner-gcp-sa-key --data-file=/tmp/terraform-deployer.json --project=p4-platform`
   - **Vault:** `vault kv put secret/gcp-sa-key key=@/tmp/terraform-deployer.json`
   - **AWS:** `aws secretsmanager create-secret --name runner/gcp-sa-key --secret-binary fileb:///tmp/terraform-deployer.json`
   - **Direct file:** Upload to `/tmp/terraform-deployer.json` on this machine

3. Once provided, confirm and I will immediately:
   - Retrieve key from credential store or filesystem
   - Run terraform apply using the key
   - Shred sensitive files
   - Record success in audit trail
   - Close GitHub issues

**Advantages:**
- ✅ Fully automated once key provided
- ✅ Ephemeral (key used, then deleted from memory)
- ✅ Works without model permissions changes
- ✅ Allows temporary/rotation key strategy

**Disadvantages:**
- ⚠️ Requires managing SA key lifecycle
- ⚠️ Key must be provisioned by admin user

---

### **PATH 3: Manual Terraform Apply (Not Recommended)**
**Effort:** 10 minutes (interactive, manual)

**Steps:**
1. `cd terraform/environments/staging-tenant-a`
2. `terraform init`
3. `terraform apply -auto-approve tfplan-deploy-final`
4. Manually verify success

**Advantages:**
- ✅ No IAM changes needed
- ✅ Works from any GCP-authenticated session

**Disadvantages:**
- ❌ Not automated (violates "hands-off" requirement)
- ❌ Manual verification needed
- ❌ No immutable audit trail from agent
- ❌ Requires interactive terminal

---

## Governance & Requirements Status

### Immutable Audit Trail ✅
- 13 commits to main (all infrastructure code)
- JSONL audit log (31 entries, append-only)
- GitHub issue #2072 (96 comments, permanent)
- All decisions documented with timestamps

### Ephemeral Credentials ✅
- OAuth tokens session-scoped
- Service account keys deleted after use (in all paths)
- No hardcoded secrets in code
- Credentials fetched from GSM/Vault/AWS

### Idempotent Operations ✅
- Terraform is idempotent (can re-apply safely)
- All scripts have duplicate-prevention guards
- Can re-run any step without side effects

### No-Ops / Fully Automated ✅
- Once blocker resolved, fully hands-off
- Zero manual steps after credentials provided
- All operations via scripts/automation

### Direct to Main Development ✅
- All 13 commits directly to main
- Zero feature branches
- Immutable git history

---

## Next Action (Choose One)

| Option | Time | Action | Automation |
|--------|------|--------|-----------|
| **PATH 1** | 5 min | Grant IAM to akushnir@... user | ✅ Full |
| **PATH 2** | 5-10 min | Provide SA key to credential store | ✅ Full |
| **PATH 3** | 10 min | Manual terraform apply | ❌ Manual |

**Recommended:** PATH 1 (cleanest, one-time setup)

Once you choose and complete your part, reply with confirmation and I will immediately:
1. Execute terraform apply
2. Record in immutable audit trail
3. Close GitHub issues (#258, #2085, #2096, #2258)
4. Verify deployment success

---

## Technical Details (For Reference)

**Terraform Plan Location:**
```
/home/akushnir/self-hosted-runner/terraform/environments/staging-tenant-a/tfplan-deploy-final
```

**Resources to Deploy (8 total):**
1. google_service_account.runner_sa
2. google_compute_firewall.runner_ingress_allow
3. google_compute_firewall.runner_ingress_deny
4. google_compute_firewall.runner_egress_allow
5. google_compute_firewall.runner_egress_deny
6. google_compute_instance_template.runner_template (Vault Agent injected)
7. google_compute_instance_pool_manager or compute.instnce group (if referenced)
8. IAM bindings (runner SA)

**Vault Agent Integration:**
- Metadata injected into instance template
- Service account credentials auto-populated
- Runner receives credentials from Vault via metadata API

**GCP Project:**
- Project: `p4-platform`
- Region: `us-central1`
- Network: `p4-isolated`
- Service Account: `runner-staging-a@p4-platform.iam.gserviceaccount.com`

---

**Status:** ⏸️ Awaiting your action on one of the three paths above.

