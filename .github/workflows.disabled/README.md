# Disabled & Archived Workflows

**Status:** 🔴 **CI/CD DISABLED FOR PRODUCTION** | **Direct-Deploy Model Active**

**Policy:** All GitHub Actions workflows that trigger on PR/push are **DISABLED** to enforce the immutable, ephemeral, idempotent, no-ops deployment model.

---

## 🚫 Disabled Workflows

### `validate-policies-and-keda.yml` (ARCHIVED)

**What it was:**
- Triggered on every PR to `main` and `staging` branches
- Ran YAML policy validation
- Executed Kubernetes dry-run on staging cluster
- Checked KEDA configuration

**Why it was disabled:**
- Violated "no-branch-development" policy (#2102)
- Created false sense of automated testing (actual deployments are manual)
- Added CI latency to PRs without production value
- Secrets fetched from GitHub, GSM, or Vault (redundant with direct-deploy model)

**Restoration:**
- File is available at `.github/workflows/archive/validate-policies-and-keda.yml`
- To restore: `git mv .github/workflows/archive/validate-policies-and-keda.yml .github/workflows/`
- Requires prior deletion of secrets and migration to direct-deploy credentials

---

## ✅ Active Workflows (workflow_dispatch only)

### `ensure-automation-files-committed.yml`

**What it does:**
- **Trigger:** Manual only (`workflow_dispatch`)
- **Action:** Verifies required automation files exist in repo
- **Rationale:** Manual check before critical runs; non-blocking

**Safe because:**
- Does NOT trigger on PR/push (manual only)
- Does NOT deploy anything (validation only)
- Does NOT interfere with direct-deploy pipeline

**Location:** `.github/workflows/ensure-automation-files-committed.yml`

---

## 📋 Workflow Audit

| Workflow | Trigger | Status | Reason |
|----------|---------|--------|--------|
| `ensure-automation-files-committed.yml` | `workflow_dispatch` | ✅ ACTIVE | Non-blocking validation |
| `validate-policies-and-keda.yml` | `pull_request` | ❌ ARCHIVED | Violates direct-deploy policy |
| `*production-deploy*` | (Any) | ❌ DELETED | Replaced with manual deployment |
| `*release*` | (Any) | ❌ DELETED | Only manual deployments allowed |
| `*terraform*` | (Any) | ❌ DELETED | Only manual applies allowed |

---

## 🚀 Current Deployment Model

**Production deployments are:**
- ✅ **Manual only** — Operator runs `scripts/deploy.sh` manually
- ✅ **Credentialed** — Secrets fetched from Vault/AWS/GSM at deploy-time
- ✅ **Audited** — Every deployment logged to immutable JSONL + GitHub comments
- ✅ **Gated** — Release gates require explicit approval
- ✅ **No CI** — GitHub Actions workflow_dispatch only, no automatic triggers

**When you push to main:**
1. ❌ NO automatic deploy
2. ❌ NO automatic tests
3. ❌ NO automatic validation
4. ✅ Code lands in repository
5. 👤 Operator manually runs `scripts/deploy.sh` to deploy

---

## 🔄 Related Issues

- **#2102:** Disable CI/PR workflows (this task)
- **#2072:** Operational handoff & audit trail
- **#2104:** Policy enforcement documentation

---

## 📚 Documentation

- **Direct Deployment Runbook:** [CREDENTIAL_PROVISIONING_RUNBOOK.md](../../CREDENTIAL_PROVISIONING_RUNBOOK.md)
- **Operational Procedures:** [OPERATIONAL_SUMMARY_DIRECT_DEPLOYMENT_2026_03_09.md](../../OPERATIONAL_SUMMARY_DIRECT_DEPLOYMENT_2026_03_09.md)
- **Deployment System:** [README_DEPLOYMENT_SYSTEM.md](../../README_DEPLOYMENT_SYSTEM.md)

---

**Last Updated:** 2026-03-09 16:10 UTC  
**Note:** This directory structure enables archival of disabled workflows while keeping the main `.github/workflows/` clean.
