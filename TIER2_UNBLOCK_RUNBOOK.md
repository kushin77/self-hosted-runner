# Tier-2: Credential Rotation & Failover — Unblock Runbook

**Status:** Tier-2 kickoff initiated; awaiting two blockers for full test automation.

## Blockers

### 1. Pub/Sub Permissions (Blocks Issue #2637 — Rotation Verification)

**Current State:**
- Script `scripts/tests/verify-rotation.sh` requires `pubsub.topics.publish` permission
- Active SA `deployer-run@nexusshield-prod.iam.gserviceaccount.com` lacks the role
- Error: `PERMISSION_DENIED: User not authorized to perform this action`

**Resolution:**
Grant `roles/pubsub.publisher` to the deployer SA (idempotent):

```bash
# Automated grant (recommended):
bash scripts/ops/grant-tier2-permissions.sh

# OR manual grant:
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:deployer-run@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/pubsub.publisher \
  --quiet
```

**Expected Outcome:**
After grant, re-run:
```bash
bash scripts/tests/verify-rotation.sh
```
Script will publish a rotate message to Pub/Sub, trigger the rotation job, and verify a new secret version is created. Test will PASS if the job completes successfully.

---

### 2. Staging Environment for Failover Tests (Blocks Issue #2638 — Failover Verification)

**Current State:**
- Script `scripts/ops/test_credential_failover.sh localhost` attempted but failed
- Reason: No API service running on localhost (baseline job creation failed)
- Requires reachable staging host running the NexusShield API

**Resolution:**
Provide a staging host with the API running:

```bash
# Example: deploy to on-prem endpoint
bash scripts/ops/test_credential_failover.sh akushnir@192.168.168.42
```

OR deploy API locally:

```bash
# (if available in your deployment scripts)
docker run -p 8080:8080 nexusshield-api:latest
# Then:
bash scripts/ops/test_credential_failover.sh localhost
```

**Expected Outcome:**
After staging is available, re-run failover tests:
```bash
bash scripts/ops/test_credential_failover.sh <staging_host>
```
Script will:
1. Create baseline migration job (test 1 — baseline)
2. Simulate GSM outage and verify Vault fallback (test 2 — failover)
3. Verify audit trail integrity (test 3)
4. Verify credential source tracking (test 4)
5. Verify job processing continuity (test 5)
6. Verify system recovery (test 6)

All tests will PASS if the endpoint is reachable and API is functional.

---

## Idempotent Permission Grants

All permissions required for Tier-2 automation are included in a single idempotent script:

```bash
PROJECT_ID=nexusshield-prod bash scripts/ops/grant-tier2-permissions.sh
```

This script grants roles to three service accounts:
1. `deployer-run@nexusshield-prod.iam.gserviceaccount.com` — rotation & testing
2. `secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com` — orchestration
3. `nxs-portal-production-v2@nexusshield-prod.iam.gserviceaccount.com` — monitoring

**Properties:**
- ✅ **Immutable:** All grants logged to JSONL audit trail (`logs/multi-cloud-audit/grant-permissions-*.jsonl`)
- ✅ **Idempotent:** Safe to re-run; checks existing permissions before granting
- ✅ **Ephemeral:** No temporary state left behind
- ✅ **No-Ops:** Run once, all permissions granted for production

---

## Full Test Re-Run (After Blockers Unblocked)

### Step 1: Grant IAM Permissions

```bash
PROJECT_ID=nexusshield-prod bash scripts/ops/grant-tier2-permissions.sh
```

Verify all grants in audit log:
```bash
cat logs/multi-cloud-audit/grant-permissions-*.jsonl
```

### Step 2: Verify Credential Rotation

```bash
bash scripts/tests/verify-rotation.sh
```

Expected: Secret version incremented, test PASSED.

Audit trail:
```bash
tail logs/multi-cloud-audit/rotation-verify-*.jsonl
```

### Step 3: Verify Credential Failover (After Staging Available)

```bash
bash scripts/ops/test_credential_failover.sh akushnir@192.168.168.42
# or
bash scripts/ops/test_credential_failover.sh localhost
```

Expected: 6 tests completed, all PASSED.

Audit trail:
```bash
tail logs/multi-cloud-audit/failover-test-*.jsonl
```

### Step 4: Update GitHub Issues

Once tests pass, comment on issues #2637 and #2638 with:
- Test result (PASSED)
- Audit log entries (immutable proof)
- Timestamp and SA used

Then mark issues as:
- `ready-for-review` → Lead engineer review → `ready-merge` → `done`

---

## Tier-2 Workflow

### Current Progress

| Task | Status | Issue | Action |
|------|--------|-------|--------|
| Deployer key rotation | ✅ DONE | #2633 | Automated owner key rotation executed, new secret in GSM |
| Sub-task creation | ✅ DONE | #2637, #2638, #2639 | Created 3 sub-tasks under #2635 |
| Ops assignment | ✅ DONE | #2634 | Ops assigned Slack webhook provisioning |
| Rotation tests | ⏳ BLOCKED | #2637 | Waiting for Pub/Sub permissions (`roles/pubsub.publisher`) |
| Failover tests | ⏳ BLOCKED | #2638 | Waiting for staging environment (API service) |
| Compliance dashboard | ⏳ NOT-STARTED | #2639 | Pending test completion |

### Tier-2 Full Acceptance Criteria

Once all blockers resolved:
- ✅ Credential rotation tests pass (rotation verified)
- ✅ Failover tests pass (GSM→Vault→KMS chain validated)
- ✅ All tests produce immutable JSONL audit logs
- ✅ Compliance dashboard deployed (monitoring rotation metrics)
- ✅ Documentation updated with runbooks
- ✅ All GitHub issues marked ready-for-review → done

---

## Immutable Audit Trail

All Tier-2 activities logged to `logs/multi-cloud-audit/`:

```bash
ls -lha logs/multi-cloud-audit/

owner-rotate-*.jsonl              # Deployer key rotation (executed)
rotation-verify-*.jsonl           # Rotation verification (blocked — needs Pub/Sub)
failover-test-*.jsonl             # Failover tests (blocked — needs staging)
grant-permissions-*.jsonl         # IAM grants (idempotent)
```

All entries are append-only (no modification/deletion). Each entry contains:
- `timestamp` — when action occurred
- `level` — INFO/WARN/ERROR
- `message` — what happened
- `hash` — SHA256 for chain integrity

---

## Next Steps

**Immediately (No Waiting):**
1. Run IAM grant script: `bash scripts/ops/grant-tier2-permissions.sh`
2. Commit to main with audit trail

**After Pub/Sub Permissions Granted:**
1. Re-run rotation verification: `bash scripts/tests/verify-rotation.sh`
2. Post results to issue #2637

**After Staging Environment Ready:**
1. Re-run failover tests: `bash scripts/ops/test_credential_failover.sh <host>`
2. Post results to issue #2638

**After Tests Pass:**
1. Update issue #2639 (compliance dashboard) with metrics
2. Mark all issues ready-for-review
3. Lead engineer approves and closes Tier-2

---

## Reference

- **Main Issue:** #2635 (TIER-2: AWS OIDC Multi-Cloud Credential Failover & Rotation Framework)
- **Sub-Issues:** #2637, #2638, #2639
- **Scripts:** `scripts/ops/grant-tier2-permissions.sh`, `scripts/tests/verify-rotation.sh`, `scripts/ops/test_credential_failover.sh`
- **Audit Trail:** `logs/multi-cloud-audit/` (append-only JSONL)

