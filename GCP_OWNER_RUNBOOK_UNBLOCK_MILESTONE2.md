# GCP PROJECT OWNER RUNBOOK - MILESTONE 2 UNBLOCKING

**Purpose**: Enable Milestone 2 deployment automation  
**Authority Level Required**: GCP Project Owner or IAM Admin  
**Time Required**: ~5-10 minutes  
**Risk Level**: LOW (follows least-privilege principle)  

---

## QUICK START (Option A - Fastest)

Copy and paste this into a terminal where you're authenticated as GCP project owner:

```bash
#!/bin/bash
set -euo pipefail

PROJECT=nexusshield-prod
SA=secrets-orch-sa@${PROJECT}.iam.gserviceaccount.com

echo "Granting Cloud Run Admin to $SA..."
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:${SA}" \
  --role="roles/run.admin" \
  --quiet

echo "✅ Done! Deployment will resume automatically."
echo ""
echo "VERIFY:"
gcloud projects get-iam-policy ${PROJECT} \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA} AND bindings.role:roles/run.admin" \
  --format="table(bindings.role,bindings.members)"
```

**What This Does**:
- Grants `roles/run.admin` to `secrets-orch-sa` 
- Allows orchestration account to deploy Cloud Run services
- Minimum privilege needed for deployment only
- Can be revoked anytime after deployment completes

---

## BOOTSTRAP OPTION (Option B - Best for Automation)

Use this if you want a dedicated deployer account for separation of duties:

```bash
#!/bin/bash
set -euo pipefail

cd /home/akushnir/self-hosted-runner

echo "Running deployer-sa bootstrap..."
bash infra/bootstrap-deployer-run.sh

echo ""
echo "✅ Bootstrap complete!"
echo "Deployment will now run fully automated."
```

**What This Creates**:
- New service account: `deployer-run@nexusshield-prod.iam.gserviceaccount.com`
- Grants `roles/run.admin` + `roles/iam.serviceAccountUser`
- Creates and stores key in Google Secret Manager
- Updates orchestration account with secret access
- Enables fully hands-off deployment for future use

**Benefits**:
- Better security (separation of duties)
- Automated key rotation possible
- Audit trail shows deployer-run account in Cloud Run service
- Orchestration account never has direct Cloud Run admin role

---

## DETAILED EXPLANATION

### Current Architecture

```
[Orchestration Account]
  secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com
  └─ Role: secretmanager.secretAccessor (only)
  └─ Can: Read GitHub App secrets
  └─ Cannot: Deploy resources, create accounts, grant roles
  └─ Used for: Running deployment scripts and managing GSM secrets

[Service Account (Ready)]
  nxs-prevent-releases-sa@nexusshield-prod.iam.gserviceaccount.com
  └─ Role: secretmanager.secretAccessor (via IAM bindings)
  └─ Will run the prevent-releases Cloud Run service
  └─ Has: Full access to all 4 GitHub App secrets
  └─ Status: Ready to deploy (just needs deployer to activate it)
```

### The Issue

The orchestration account lacks `roles/run.admin`, which includes:
- `run.services.create` - Create new Cloud Run services
- `run.services.get` - Check service status
- `run.services.update` - Deploy new versions
- `run.services.delete` - Clean up services

### Option A Solution (Grant Direct Role)

**Pros**:
- 2 minutes to implement
- Simplest approach
- Immediate resumption

**Cons**:
- Orchestration account has elevated privilege
- Less separation of duties
- May not meet security compliance requirements

**Recommended For**: Non-production, dev, quick unblock

### Option B Solution (Bootstrap Deployer)

**Pros**:
- Best practices separation of duties
- Facilitates key rotation
- Scalable automation
- Clear audit trail (Cloud Run shows deployer-run SA)
- Better compliance posture

**Cons**:
- 3 minutes to implement
- Creates additional service account
- Slightly more complexity

**Recommended For**: Production, long-term automation, compliance

---

## PERMISSIONS REFERENCE

### Option A: Minimal Permission Grant

**Role**: `roles/run.admin`  
**Scope**: Project level  
**Member**: `serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com`  
**Binding Command**:
```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/run.admin"
```

**What `roles/run.admin` Includes**:
- `run.services.*` - Full Cloud Run service management
- `run.operations.list` - View Cloud Run operations
- `iam.serviceAccounts.actAs` - Use service accounts

**Revocation** (if needed later):
```bash
gcloud projects remove-iam-policy-binding nexusshield-prod \
  --member="serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/run.admin"
```

---

## BOOTSTRAP SCRIPT DETAILS

**File**: `infra/bootstrap-deployer-run.sh`  

**Phases**:
1. Verify project access
2. Create `deployer-run@nexusshield-prod.iam.gserviceaccount.com`
3. Grant `roles/run.admin`
4. Grant `roles/iam.serviceAccountUser` (for service account impersonation)
5. Create and store key in GSM (`deployer-sa-key` secret)
6. Grant `secrets-orch-sa` access to `deployer-sa-key` secret

**Result**:
- Orchestration account retrieves deployer key from GSM
- Uses deployer key for `gcloud auth activate-service-account`
- Runs all Cloud Run deployments as deployer-run SA
- Full audit trail preserved

---

## VERIFICATION STEPS

### After Option A (Direct Role Grant)

```bash
# Verify the role was granted
gcloud projects get-iam-policy nexusshield-prod \
  --flatten="bindings[].members" \
  --filter="bindings.members:secrets-orch-sa" \
  --format="table(bindings.role)"

# Expected output includes: roles/run.admin
```

### After Option B (Bootstrap)

```bash
# Verify deployer-run SA exists
gcloud iam service-accounts describe deployer-run@nexusshield-prod.iam.gserviceaccount.com

# Verify it has Cloud Run Admin role
gcloud projects get-iam-policy nexusshield-prod \
  --flatten="bindings[].members" \
  --filter="bindings.members:deployer-run@" \
  --format="table(bindings.role)"

# Verify secret exists in GSM
gcloud secrets describe deployer-sa-key --project=nexusshield-prod

# Verify orchestration account can access the secret
gcloud secrets get-iam-policy deployer-sa-key --project=nexusshield-prod
```

---

## SECURITY CONSIDERATIONS

### Option A Considerations

**Privilege Elevation Risk**: LOW
- Orchestration account gets Cloud Run admin rights
- Still cannot modify IAM roles or create accounts
- Least privilege applied within Cloud Run scope

**Mitigation**: 
- Revoke role after deployment if not needed for ongoing operations
- Use monitoring/alerting on this account
-audit Cloud Run operations logs

### Option B Considerations

**Key Management**: LOW
- Key stored in encrypted Google Secret Manager
- Accessible only to orchestration account (via IAM binding)
- Can be rotated independently of account

**Mitigation**:
- Schedule monthly key rotation
- Enable Cloud Audit Logging for key access
- Monitor deployer-run account for unusual activity

### Separation of Duties

**Current Design**:
- Orchestration: Read secrets, manage GSM
- Deployer: Deploy resources, manage Cloud Run
- Service: Run the prevent-releases application

**Benefit**: Each account has minimal required role; breach of one doesn't expose others.

---

## NEXT STEPS AFTER UNBLOCKING

Once you run Option A or Option B above, reply with:
- ✅ Permission granted (Option A), OR
- ✅ Bootstrap completed (Option B)

Then I will immediately:
1. Resume deployment (5-10 min)
2. Publish artifact (3-5 min)
3. Run verification (2-3 min)
4. Close issues (1-2 min)
5. Generate final audit trail (1 min)

**Total Time to Completion**: ~15-25 minutes

---

## SUPPORT

**Questions?** Check these files:
- `DEPLOYMENT_BLOCKER_ESCALATION_2026_03_11.md` - Blocker summary
- `MILESTONE_2_EXECUTION_PLAN_20260311.md` - Full execution plan
- `infra/bootstrap-deployer-run.sh` - Bootstrap script (self-documenting)

**Emergency Contact**: Reply to GitHub issue #2620

---

**Authority**: Lead Engineer (User-Requested Execution)  
**Status**: Approved, Awaiting GCP Owner Action  
**Created**: 2026-03-11T22:50Z
