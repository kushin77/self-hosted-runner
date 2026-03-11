# 🔑 Key Rotation Handoff for Project Owner

**Date:** 2026-03-11  
**Status:** ⏳ Awaiting owner execution  
**Lead Engineer:** Autonomous Orchestrator (Lead approved)

---

## 📋 Summary

The deployment is **live and operational** (Cloud Run service: `prevent-releases`). To enable **automated key rotation** and grant the deployer service account self-rotation rights, the **Project Owner** must run a single idempotent script.

---

## ✅ What the Owner Script Does

1. **Grants IAM Roles** to deployer-run service account:
   - `roles/iam.serviceAccountKeyAdmin` — can create/delete own keys
   - `roles/secretmanager.secretAccessor` — can read own secrets
   - `roles/secretmanager.secretVersionAdder` — can add secret versions

2. **Creates a New Key** for `deployer-run@nexusshield-prod.iam.gserviceaccount.com`

3. **Stores New Key** in Secret Manager under `deployer-sa-key` (as a new version)

4. **Verifies Access** — tests that the new key works

All operations are **idempotent** (safe to run multiple times) and produce an **immutable audit trail** (JSONL).

---

## 🚀 Instructions for Project Owner

### Prerequisites

- You have **Project Owner** or **Editor** IAM role in `nexusshield-prod`
- You are authenticated to GCP (`gcloud auth login`)

### Step 1: Navigate to Repository

```bash
cd /home/akushnir/self-hosted-runner
```

### Step 2: Run the Owner Orchestration Script

```bash
bash infra/owner-complete-rotation-orchestration.sh
```

**Expected output:**
```
✅ COMPLETE: Full key rotation + permission grant

What happened:
  1. ✅ Granted deployer-run@...:
     - roles/iam.serviceAccountKeyAdmin
     - roles/secretmanager.secretAccessor
     - roles/secretmanager.secretVersionAdder on secret 'deployer-sa-key'

  2. ✅ Created new key and added to Secret Manager

  3. ✅ Verified new key has access to project

Audit trail: /tmp/owner-complete-rotation-TIMESTAMP.jsonl

Next steps (automatic, lead engineer):
  1. Lead engineer will detect new secret version
  2. Cloud Run services will be redeployed with new key
  3. Monitoring will be updated and issues closed
```

### Step 3: Verify Success

The script will output an audit log path (e.g., `/tmp/owner-complete-rotation-20260311-233045.jsonl`). You can inspect it:

```bash
cat /tmp/owner-complete-rotation-20260311-233045.jsonl | jq .
```

---

## 🔄 Automatic Lead-Engineer Actions (After Owner Runs Script)

Once you execute the script above, the **lead engineer watcher** (running in background on this machine) will:

1. **Detect** the new secret version
2. **Automatically activate** the new key
3. **Verify** deployer access to the project
4. **Update** GitHub issues to reflect completion
5. **Restart** services as needed

**The lead engineer requires NO additional input.** Everything is automated.

---

## 📊 Current Status

### ✅ Completed
- [x] Cloud Run service deployed (`prevent-releases`)
- [x] Deployer SA created (`deployer-run@nexusshield-prod.iam.gserviceaccount.com`)
- [x] Initial key stored in Secret Manager
- [x] Service is healthy and responding
- [x] Local uptime watcher running
- [x] Audit logs committed to Git

### ⏳ Awaiting Owner
- [ ] **Owner runs:** `bash infra/owner-complete-rotation-orchestration.sh`

### ⏸️ Auto-Trigger (Lead Engineer)
- [ ] Auto-detect new key version → activate
- [ ] Restart services
- [ ] Update GitHub issues
- [ ] Close deployment tickets

---

## 🔐 Security Notes

- **Immutable:** All actions logged to JSONL (append-only) + Git commits
- **Ephemeral:** Temporary key files securely shredded (3-pass overwrite)
- **Idempotent:** Script can be re-run safely without side effects
- **No-Ops:** Zero manual operations after owner runs script
- **Hands-Off:** Lead engineer fully automated once key is rotated

---

## ❓ Troubleshooting

### Script Output: "Permission denied: setIamPolicy"
- **Cause:** You need Project Owner role
- **Fix:** Ask a member with Owner role to run the script

### Script Output: "Failed to create key" (Step 2)
- **Cause:** Rare; usually transient GCP API issue
- **Fix:** Re-run the script (idempotent)

### Audit Log Shows "Failed to activate new key"
- **Cause:** Could indicate a KMS/Secret Manager configuration issue
- **Fix:** Check Secret Manager permissions and KMS key access for the deployer SA

---

## 📎 Reference Files

- **Owner Script:** [infra/owner-complete-rotation-orchestration.sh](infra/owner-complete-rotation-orchestration.sh)
- **Lead Engineer Watcher:** [infra/auto-detect-key-rotation-lead-engineer.sh](infra/auto-detect-key-rotation-lead-engineer.sh)
- **Audit Logs:** `/tmp/owner-complete-rotation-*.jsonl` and `/tmp/auto-detect-watcher.out`
- **Git Commit:** Latest commit includes rotation orchestration scripts

---

## 📋 Appendix: Manual Cleanup (Post-Rotation)

After the new key is active and services are stable, you may optionally delete old key versions:

```bash
# List all key versions
gcloud iam service-accounts keys list \
  --iam-account=deployer-run@nexusshield-prod.iam.gserviceaccount.com \
  --project=nexusshield-prod

# Delete old key (replace KEY_ID with actual ID)
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=deployer-run@nexusshield-prod.iam.gserviceaccount.com \
  --project=nexusshield-prod
```

---

**Lead Engineer Approved** — Ready for automated execution once owner completes their step.
