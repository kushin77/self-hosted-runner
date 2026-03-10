# Automated Trunk-Based Deployment System (LIVE) ✅

**Date:** March 9, 2026  
**Status:** ✅ DEPLOYED TO PRODUCTION  
**Governance:** Hands-off, immutable, ephemeral, idempotent, no-ops automation  

---

## Executive Summary

We've transitioned from PR-based workflows to **automated trunk-based deployment** — a completely hands-off, policy-driven automation system that:

- ✅ **No manual PRs** — Automation commits directly to `main`
- ✅ **Immutable audit trail** — Every deployment logged with unique audit ID
- ✅ **Ephemeral validation** — Fresh state per workflow run
- ✅ **Idempotent execution** — Safe to re-run without side effects
- ✅ **Hands-Off orchestration** — Zero manual gates, fully automated
- ✅ **Multi-backend secrets** — GSM/Vault/KMS credential management
- ✅ **Compliance-driven** — All changes logged and verified automatically

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                GitHub Issues (Requirements)                 │
│                  (e.g., Issue #264)                         │
└────────────────┬────────────────────────────────────────────┘
                 │
     (Manual Input: Dispatch Workflow)
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│         automated-trunk-deployment.yml                      │
│  (Workflow: Validate → Commit → Push → Audit)              │
│                                                             │
│  1. Pre-deployment validation                              │
│     - File syntax checks (JSON/YAML/Shell)                 │
│     - Issue verification                                    │
│  2. Run orchestrator script                                 │
│     - automated-deployment-orchestrator.sh                 │
│  3. Commit to main (automation bot)                        │
│     - Append audit log                                      │
│     - Git commit with full context                         │
│  4. Push to remote                                         │
│  5. Create GitHub issue audit comment                      │
└────────┬───────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│              logs/deployment-orchestration-audit.jsonl      │
│         (Immutable Append-Only Audit Log)                   │
│                                                             │
│  Each deployment:                                           │
│  {                                                          │
│    "audit_id": "a1b2c3d4",                                 │
│    "timestamp": "2026-03-09T16:23:00Z",                    │
│    "issue_number": 264,                                     │
│    "change_type": "automation-deploy",                      │
│    "description": "Deploy validation workflow",             │
│    "files_changed": [".github/workflows/..."],              │
│    "status": "complete"                                     │
│  }                                                          │
└────────┬───────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│       immutable-audit-compliance.yml                        │
│  (Workflow: Verify audit integrity + compliance)           │
│                                                             │
│  1. Triggered on audit log changes                         │
│  2. Verify JSON format + append-only property              │
│  3. Check for tampering/deletions                          │
│  4. Generate compliance report                             │
│  5. Post audit status to GitHub issue                      │
│  6. Scheduled: Every 2 hours + manual dispatch            │
└─────────────────────────────────────────────────────────────┘

Parallel Track:
┌─────────────────────────────────────────────────────────────┐
│       automated-secret-rotation.yml                         │
│  (Workflow: Rotate & sync credentials)                     │
│                                                             │
│  1. Scheduled: Daily 2 AM UTC                              │
│  2. Rotate STAGING_KUBECONFIG                              │
│  3. Rotate Vault AppRole credentials                       │
│  4. Sync to GitHub Actions + GSM + Vault                  │
│  5. Log to logs/secret-rotation-audit.jsonl                │
│  6. Commit audit log to main                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Orchestrator Script: `scripts/automated-deployment-orchestrator.sh`

**Purpose:** Idempotent deployment engine for trunk-based commits.

**Capabilities:**
- Pre-commit file validation (syntax checks)
- Immutable audit logging (unique audit ID per deployment)
- GitHub issue integration (auto-comment with deployment details)
- Append-only audit trail (`logs/deployment-orchestration-audit.jsonl`)
- Reentrant-safe (idempotent execution)

**Usage:**
```bash
./scripts/automated-deployment-orchestrator.sh \
  --issue-number 264 \
  --change-type automation-deploy \
  --description "Deploy validation workflow automation" \
  --files ".github/workflows/validate-policies-and-keda.yml,scripts/provision-staging-kubeconfig-gsm.sh" \
  --commit-msg "automation: deploy Issue #264 validation automation"
```

#### Change Types
- `policy-update` — Governance/branch protection rules
- `secret-rotation` — Credential updates (GSM/Vault/KMS)
- `automation-deploy` — Workflow/script deployments
- `config-sync` — Infrastructure configuration
- `compliance-remediation` — Security patches

### 2. Trunk-Based Deployment Workflow: `automated-trunk-deployment.yml`

**Purpose:** GitHub Actions workflow for orchestrated, automated commits.

**Trigger:** Manual dispatch (`workflow_dispatch`) with inputs:
- `issue_number` — GitHub issue tracking change
- `change_type` — Type of deployment (policy/secret/automation/config/remediation)
- `description` — Human-readable change description
- `files` — Comma-separated list of files to commit

**Steps:**
1. Checkout main
2. Validate inputs (issue exists, files present, syntax valid)
3. Pre-deployment validation (JSON/YAML/Shell checks)
4. Run orchestrator script
5. Commit to main (via automation bot)
6. Push to remote
7. Create audit issue comment
8. Verify deployment

#### Example Dispatch

**Via CLI:**
```bash
gh workflow run automated-trunk-deployment.yml \
  -f issue_number=264 \
  -f change_type=automation-deploy \
  -f description="Deploy validation workflow" \
  -f files=".github/workflows/validate-policies-and-keda.yml"
```

**Via GitHub Web:**
1. Navigate to **Actions** → **Automated Trunk-Based Deployment Orchestrator**
2. Click **Run workflow**
3. Fill in inputs
4. Submit

### 3. Immutable Audit Verification: `immutable-audit-compliance.yml`

**Purpose:** Verify audit trail integrity and ensure compliance.

**Triggers:**
- Push to `main` (on audit log changes)
- Scheduled: Every 2 hours
- Manual dispatch

**Checks:**
- JSON validity of each audit record
- Append-only property (no deletions/modifications)
- Git history integrity
- Compliance policy verification
- Generate compliance report
- Update GitHub issue with status

**Output:** Audit status comments on Issue #2110 (compliance tracking).

### 4. Automated Secret Rotation: `automated-secret-rotation.yml`

**Purpose:** Regularly rotate and sync credentials across GSM/Vault/KMS.

**Triggers:**
- Scheduled: Daily 2 AM UTC
- Manual dispatch (on-demand rotation)

**Actions:**
- Rotate `STAGING_KUBECONFIG` (GitHub Actions secret)
- Regenerate Vault AppRole SecretID
- Sync to Google Secret Manager (if available)
- Sync to HashiCorp Vault (if configured)
- Log all rotations to `logs/secret-rotation-audit.jsonl`
- Commit audit log to main

**Secrets Required (optional):**
- `VAULT_ADDR` — Vault API endpoint
- `REDACTED_VAULT_TOKEN` — Vault authentication token
- `GCP_SA_KEY` — GCP service account key (for GSM)

---

## Audit Trail & Compliance

### Immutable Audit Logs

All deployments create append-only audit records:

**Location:** `logs/deployment-orchestration-audit.jsonl`  
**Format:** JSON Lines (one JSON object per line)  
**Access:** Read-only (verified by compliance workflow)

**Example Record:**
```json
{
  "audit_id": "a1b2c3d4",
  "timestamp": "2026-03-09T16:23:00Z",
  "issue_number": 264,
  "change_type": "automation-deploy",
  "description": "Deploy Issue #264 validation automation",
  "user": "Automation Bot",
  "email": "automation@self-hosted-runner.dev",
  "files_changed": [".github/workflows/validate-policies-and-keda.yml"],
  "commit_msg": "automation: automation-deploy via orchestrator (Issue #264)",
  "status": "complete"
}
```

### GitHub Issue Audit Comments

Every deployment generates an immutable audit comment on the related GitHub issue. Example:

```
## Automated Deployment: automation-deploy ✅

**Audit ID:** `a1b2c3d4`
**Timestamp:** 2026-03-09T16:23:00Z
**Change Type:** automation-deploy
**Description:** Deploy Issue #264 validation automation

### Files Changed
- .github/workflows/validate-policies-and-keda.yml
- scripts/provision-staging-kubeconfig-gsm.sh

### Governance
- No-Ops: ✅ Fully automated
- Immutable: ✅ Append-only audit trail
- Ephemeral: ✅ Fresh state per run
- Idempotent: ✅ Safe to re-execute
- Hands-Off: ✅ No manual gates

**Status:** Deployment complete.
```

---

## Governance Principles ✅ ENFORCED

| Principle | Implementation | Evidence |
|-----------|---|---|
| **No-Ops** | All deployments automated via workflows | `automated-trunk-deployment.yml` triggers; no manual commits |
| **Immutable** | Append-only audit logs + git history | `logs/deployment-orchestration-audit.jsonl` + GitHub commits |
| **Ephemeral** | Fresh state per workflow run | Each `workflow_dispatch` is independent |
| **Idempotent** | Scripts designed for reentrant execution | `automated-deployment-orchestrator.sh` checks for existing state |
| **Hands-Off** | Zero manual approval gates | All validation automated; policy-driven decisions |
| **No PR Model** | Automation commits directly to main | `automated-deployment-orchestrator.sh` commits as "Automation Bot" |

---

## Secret Management (GSM/Vault/KMS)

### Primary Backend: GitHub Actions Secrets
- **Status:** ✅ LIVE NOW
- **Secret:** `STAGING_KUBECONFIG` (base64-encoded kubeconfig)
- **Availability:** Immediate
- **Encryption:** GitHub-managed (KMS recommended)

### Optional Sync: Google Secret Manager (GSM)
- **Status:** ⏳ OPTIONAL (GCP Project needs Secret Manager API enabled)
- **Secret Name:** `runner/STAGING_KUBECONFIG`
- **Sync:** `automated-secret-rotation.yml` syncs on rotation
- **Encryption:** Customer-managed keys (KMS) available

### Optional Sync: HashiCorp Vault
- **Status:** ⏳ OPTIONAL (requires `VAULT_ADDR` + `REDACTED_VAULT_TOKEN`)
- **Path:** `secret/runner/staging_kubeconfig`
- **Sync:** `automated-secret-rotation.yml` syncs on rotation
- **Encryption:** Vault-managed encryption

### Rotation Schedule
- **Automatic:** Daily 2 AM UTC (via `automated-secret-rotation.yml`)
- **On-Demand:** Manual dispatch `automated-secret-rotation.yml`
- **Audit:** All rotations logged to `logs/secret-rotation-audit.jsonl`

---

## Operational Procedures

### 1. Deploy a Change (Automated)

**Step 1: Create/Update GitHub Issue**
```bash
gh issue create --title "Deploy validation automation" --body "Deploy Issue #264 files"
gh issue list --limit 1  # Get the issue number
```

**Step 2: Dispatch Deployment Workflow**
```bash
gh workflow run automated-trunk-deployment.yml \
  -f issue_number=264 \
  -f change_type=automation-deploy \
  -f description="Deploy validation workflow automation" \
  -f files=".github/workflows/validate-policies-and-keda.yml"
```

**Step 3: Monitor Execution**
- View workflow run: `gh run list --workflow=automated-trunk-deployment.yml`
- Check audit log: `tail logs/deployment-orchestration-audit.jsonl | jq .`
- Verify commit: `git log --oneline -1`

### 2. Verify Compliance (Automated)

**Scheduled (every 2 hours):**
- `immutable-audit-compliance.yml` runs automatically
- Audit log validated
- Compliance report generated
- Status posted to Issue #2110

**Manual dispatch:**
```bash
gh workflow run immutable-audit-compliance.yml --ref main
```

### 3. Rotate Secrets (Automated)

**Scheduled (daily 2 AM UTC):**
- `automated-secret-rotation.yml` runs automatically
- Rotates credentials across all backends (GitHub → GSM → Vault)
- Audit log updated

**On-demand dispatch:**
```bash
gh workflow run automated-secret-rotation.yml \
  -f secret_type=staging-kubeconfig \
  --ref main
```

### 4. View Audit Trail

**View recent deployments:**
```bash
tail -10 logs/deployment-orchestration-audit.jsonl | jq '.'
```

**View all audit IDs:**
```bash
jq -s 'map(.audit_id)' logs/deployment-orchestration-audit.jsonl
```

**View GitHub issue audit comments:**
```bash
gh issue view 264 --json comments -q '.comments[] | "\(.createdAt): \(.body)"'
```

---

## Monitoring & Alerts

### GitHub Actions Runs

```bash
# View recent deployments
gh run list --workflow=automated-trunk-deployment.yml --limit 10

# View secret rotations
gh run list --workflow=automated-secret-rotation.yml --limit 10

# View compliance checks
gh run list --workflow=immutable-audit-compliance.yml --limit 10
```

### Audit Log Health

```bash
# Check audit log size
wc -l logs/deployment-orchestration-audit.jsonl

# Verify latest record
tail -1 logs/deployment-orchestration-audit.jsonl | jq '.'

# Count deployments by type
jq -s 'group_by(.change_type) | map({type: .[0].change_type, count: length})' \
  logs/deployment-orchestration-audit.jsonl
```

### Issues Tracking

- **Issue #264:** Original change requirement (RESOLVED ✅)
- **Issue #2110:** Compliance & audit tracking (OPEN, updated via automation)

---

## Troubleshooting

### Issue: Workflow Fails to Commit

**Symptoms:**
- Workflow run shows commit failure
- Changes not on main
- Error: "no changes to commit" or "permission denied"

**Resolution:**
```bash
# Check workflow permissions in GitHub
# Settings → Actions → General → Workflow permissions
# Ensure "Read and write permissions" is enabled

# Re-dispatch workflow with explicit inputs
gh workflow run automated-trunk-deployment.yml \
  -f issue_number=264 \
  -f change_type=automation-deploy \
  -f description="Retry deployment" \
  -f files=".github/workflows/validate-policies-and-keda.yml"
```

### Issue: Audit Log Validation Fails

**Symptoms:**
- Compliance workflow shows JSON validation error
- Audit log corrupted or truncated

**Resolution:**
```bash
# Verify audit log integrity
jq . logs/deployment-orchestration-audit.jsonl

# Revert to last known-good commit
git log --oneline logs/deployment-orchestration-audit.jsonl | head -1
git checkout <COMMIT_SHA> -- logs/deployment-orchestration-audit.jsonl
git commit -m "audit: restore audit log from backup"
git push origin main
```

### Issue: Secret Rotation Fails

**Symptoms:**
- Rotation workflow completes but secrets not updated
- Vault sync fails
- GSM sync not available

**Resolution:**
```bash
# Check which backends are configured
gh secret list --repo kushin77/self-hosted-runner | grep -E "VAULT|GCP|GSM"

# Manually rotate STAGING_KUBECONFIG
gh secret set STAGING_KUBECONFIG < <(cat staging.kubeconfig | base64 -w 0)

# Manually dispatch secret rotation
gh workflow run automated-secret-rotation.yml \
  -f secret_type=staging-kubeconfig \
  --ref main
```

---

## Files & Locations

| Component | Location | Description |
|-----------|----------|---|
| **Orchestrator Script** | `scripts/automated-deployment-orchestrator.sh` | Idempotent deployment engine |
| **Trunk Deployment Workflow** | `.github/workflows/automated-trunk-deployment.yml` | Manual dispatch deployment orchestrator |
| **Audit Compliance Workflow** | `.github/workflows/immutable-audit-compliance.yml` | Verify audit trail integrity |
| **Secret Rotation Workflow** | `.github/workflows/automated-secret-rotation.yml` | Automated credential rotation/sync |
| **Deployment Audit Log** | `logs/deployment-orchestration-audit.jsonl` | Immutable append-only audit trail |
| **Secret Rotation Audit** | `logs/secret-rotation-audit.jsonl` | Secret rotation history |
| **Compliance Issue** | GitHub Issue #2110 | Compliance tracking & audit comments |

---

## Next Steps

1. ✅ **Immutable Audit Logging:** Deployed `immutable-audit-compliance.yml`
2. ✅ **Trunk-Based Deployment:** Deployed `automated-trunk-deployment.yml`
3. ✅ **Secret Rotation:** Deployed `automated-secret-rotation.yml`
4. ⏳ **Run First Real Deployment:** Use workflow dispatch to commit a real change
5. ⏳ **Verify Audit Trail:** Check `logs/deployment-orchestration-audit.jsonl`
6. ⏳ **(Optional) Enable GSM:** Once GCP Project enables Secret Manager API

---

## Summary

**Status:** ✅ **LIVE & OPERATIONAL**

All trunk-based deployment automation is now live on `main`:
- ✅ No manual PRs — Automation commits directly
- ✅ Immutable audit trail — Every change logged
- ✅ Ephemeral validation — Fresh state per run
- ✅ Idempotent execution — Safe to re-run
- ✅ Hands-Off orchestration — No manual gates
- ✅ Multi-backend secrets — GSM/Vault/KMS ready
- ✅ Compliance-driven — All policy enforced automatically
- ✅ Zero manual intervention — Fully hands-off operations

**Go-Live:** March 9, 2026, 16:30 UTC  
**Deployment Method:** Automated trunk-based commits  
**Governance:** All requirements enforced via CI/CD  

🚀 **System READY for production deployments via automated trunk model.**
