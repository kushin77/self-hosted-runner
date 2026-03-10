# Deployment Resume Checklist — GCP Access Diagnostic

**Framework Status:** ✅ COMPLETE, IMMUTABLE, READY  
**Blocker:** GCP project `p4-platform` not accessible  
**Action:** Verify GCP access, then run resume script  

---

## Step 1: Verify GCP Access

Run this diagnostic to identify which scenario applies:

```bash
# Test 1: List accessible projects
gcloud projects list --filter="name~'p4-platform'" --format="value(projectId,name)"

# Test 2: Describe the project
gcloud projects describe p4-platform 2>&1

# Test 3: List all projects you have access to
gcloud projects list --limit=20

# Test 4: Check current active project
gcloud config get-value project

# Test 5: Check authenticated user
gcloud auth list --filter=status:ACTIVE --format="value(account)"
```

**Expected output:**
- One of the above should show `p4-platform` with your user listed
- If ALL fail or don't show p4-platform → you need GCP project owner to grant access

---

## Step 2: Resume Deployment

Once you confirm GCP access to `p4-platform`, run:

```bash
cd /home/akushnir/self-hosted-runner

# Option A: Automated resume (if you have SA key creation permissions)
./scripts/complete-deployment-oauth-apply.sh

# Option B: Manual single command
terraform -chdir=terraform/environments/staging-tenant-a apply -auto-approve tfplan-deploy-final
```

---

## Step 3: Verify Success

```bash
# Check result
cat deploy_apply_result.txt

# Check audit trail
tail -5 logs/deployment-provisioning-audit.jsonl | jq .

# Check GitHub
gh issue view 2072 --comments
```

---

## If GCP Access Issue Persists

**Scenario A: Project doesn't exist in your org**
- Contact GCP admin to create `p4-platform` project in correct org
- OR confirm correct project ID with your team

**Scenario B: You lack permissions**
- Contact GCP project owner to grant:
  - `roles/iam.serviceAccountAdmin`
  - `roles/compute.admin`
  - `roles/serviceusage.serviceUsageAdmin`

**Scenario C: Wrong org/context**
- Run: `gcloud config set core/project p4-platform`
- OR: `gcloud auth application-default login`

---

## Deployment Resume Script (Ready to Run)

Commit ready: `1e0592c7c`  
Terraform plan: `terraform/environments/staging-tenant-a/tfplan-deploy-final`  
All scripts: Ready in `scripts/` directory  

**Just run the diagnostic above and report back.**
