# IMMEDIATE GCP UNBLOCKING GUIDE - Phase 3 Deployment

## 🚨 Current Status: BLOCKED ON GCP PERMISSIONS

**Timestamp:** 2026-03-09 18:45 UTC  
**Blocker:** User `akushnir@bioenergystrategies.com` lacks GCP project admin permissions  
**Solution:** GCP Project Owner/Admin must execute 2 commands below

---

## ⚠️ What's Blocked

Terraform fully prepared to deploy 8 infrastructure resources. Execution blocked at **2 GCP-level access gates**:

1. **Compute Engine API** - Not enabled on project `p4-platform`
2. **IAM Role** - `iam.serviceAccountAdmin` not granted to deployer user

---

## 🔑 GCP Project Owner/Admin Required

Only someone with **GCP Project Owner** or **Organization Admin** privileges can execute these commands.

**Candidates:**
- GCP Project Owner (bioenergystrategies.com)
- GCP Organization Administrator
- User with `roles/owner` or `roles/editor` on project

---

## ✅ Commands to Execute (Copy-Paste)

### Command 1: Enable Compute Engine API
```bash
gcloud services enable compute.googleapis.com --project=p4-platform
```
**Expected output:**
```
Operation "operations/acf.p4..." completed successfully.
```

### Command 2: Grant IAM Role
```bash
gcloud projects add-iam-policy-binding p4-platform \
  --member=user:akushnir@bioenergystrategies.com \
  --role=roles/iam.serviceAccountAdmin
```
**Expected output:**
```
Updated IAM policy for project [p4-platform].
bindings:
- members:
  - user:akushnir@bioenergystrategies.com
  role: roles/iam.serviceAccountAdmin
```

### Command 3: Wait 2-3 Minutes
```bash
sleep 180
```
*Allows GCP to propagate policy changes across all systems.*

---

## 🚀 After GCP Admin Completes: Auto-Execute Final Deployment

Once GCP admin completes the 3 commands above, **one-shot unblock script** will:

1. Immediately re-run terraform apply
2. Deploy all 8 infrastructure resources
3. Record success in immutable audit trail
4. Close all GitHub deployment issues

```bash
cd /home/akushnir/self-hosted-runner
bash scripts/phase3b-unblock-and-deploy.sh
```

---

## 📋 What Gets Deployed

Once unblocked, terraform will create:

| # | Resource | Type | Status |
|---|----------|------|--------|
| 1 | runner-sa | Service Account | Ready |
| 2 | runner_ingress_deny | Firewall Rule | Ready |
| 3 | runner_egress_deny | Firewall Rule | Ready |
| 4 | runner_ingress_allow | Firewall Rule | Ready |
| 5 | runner_egress_allow | Firewall Rule | Ready |
| 6 | runner_template | Instance Template | Ready |
| 7 | Workload Identity (1) | IAM Binding | Ready |
| 8 | Workload Identity (2) | IAM Binding | Ready |

**Total Deployment Time:** ~30 seconds (once APIs/IAM ready)

---

## 📞 Escalation

If you don't have GCP project admin access:

1. **Contact:** GCP Project Owner from bioenergystrategies.com
2. **Send them:** This document + the 3 commands above
3. **Approval:** Already pre-approved by deployment user
4. **Timeline:** ~5 minutes total (3 commands + 3-min wait + auto-deploy)

---

## 🎯 Goal

**Zero additional work after GCP admin executes 2 commands.**

- ✅ Terraform configuration: READY
- ✅ Deployment scripts: READY
- ✅ Credentials management: READY
- ✅ Audit trail system: READY
- ⏳ GCP project access: **AWAITING ADMIN ACTION ONLY**

---

## 📝 Verification

**To verify prerequisites are met:**

```bash
# Check if Compute Engine API is enabled
gcloud services list --enabled --project=p4-platform | grep compute

# Check if user has iam.serviceAccountAdmin role
gcloud projects get-iam-policy p4-platform \
  --flatten="bindings[].members" \
  --filter="members:akushnir@bioenergystrategies.com AND bindings.role:iam.serviceAccountAdmin"
```

If both return results → Ready to proceed to `phase3b-unblock-and-deploy.sh`

---

## 🔐 Security Notes

- ✅ All credentials in GSM/Vault (never in code)
- ✅ IAM role is narrowly scoped (iam.serviceAccountAdmin only)
- ✅ All operations logged immutably (JSONL audit trail)
- ✅ Ephemeral keys rotated automatically (24-hour lifecycle)
- ✅ No persistent credentials on disk (GSM metadata injection)

---

**Status:** ✋ WAITING FOR GCP ADMIN ACTION  
**Next Step:** Execute 3 commands above, then run `phase3b-unblock-and-deploy.sh`  
**ETA:** 5 minutes from now (3 commands + 3-min wait + 30-sec deploy)

