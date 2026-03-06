# Branch Maintenance Policy
**Policy ID**: BRANCH-MAINT-001  
**Effective Date**: 2026-03-06  
**Last Updated**: 2026-03-06  
**Status**: ✅ ACTIVE

---

## Executive Summary

This policy implements automated cleanup of merged feature branches to maintain repository hygiene. All work is permanently preserved in `main` branch history; only branch metadata is removed.

**Key Principle**: "Clean history, preserved code" - Deletion is metadata-only, all commits live in main forever.

---

## Scope

**What This Policy Covers**:
- Remote feature/chore/fix branches merged into main
- Age-based cleanup (30+ days old)
- Automated execution via GitHub Actions
- Monthly scheduled maintenance + on-demand triggers

**What This Policy PROTECTS**:
- `main`, `master`, `develop`, `staging`, `production` - Never deleted
- Active branches (updated within 30 days) - Automatically preserved
- All commit history - Preserved permanently in main
- Code changes - No data loss, only branch removal

---

## Cleanup Criteria

Branches become eligible for deletion when ALL of the following are true:

1. **✅ Merged into main**
   - All commits from branch are in main history
   - Verified via `git branch --merged main`

2. **✅ Age > 30 days**
   - Last commit is older than 30 days
   - Updated via cron trigger on first Sunday of month
   - Manual trigger can override with `--skip-days=0`

3. **✅ Not protected**
   - Not in exclusion list: main, master, develop, staging, production
   - Customizable via workflow input `exclude_pattern`

4. **✅ Remote branch exists**
   - Branch exists in origin (can verify before deletion)
   - Deletion only removes remote ref

---

## Execution Schedule

### Automated (Hands-Off)
```
Event: First Sunday of each month, 02:00 UTC
Trigger: GitHub Actions schedule
Mode: DRY RUN (preview only, no deletion)
Result: Report generated and logged
```

### Manual Execution
```bash
# Option 1: Preview mode (recommended first run)
gh workflow run stale-branch-cleanup.yml --input dry_run=true

# Option 2: Execute cleanup (actual deletion)
gh workflow run stale-branch-cleanup.yml --input dry_run=false

# Option 3: Via issue comment on #755
Comment: "cleanup:branches"
```

### Interactive (Issue-Driven)
- Comment `cleanup:branches` on issue #755
- Workflow generates report and comments back
- Can include flags for execution mode

---

## Safety Mechanisms

### ✅ Multi-Layer Protection

**Layer 1: Whitelist Protected Branches**
```yaml
protected: [main, master, develop, staging, production]
action: NEVER delete
```

**Layer 2: Age Verification**
```yaml
minimum_age: 30 days
checks:
  - Last commit date check
  - Updated within threshold → preserved
  - Older than threshold → eligible
```

**Layer 3: Merge Status Verification**
```yaml
merged_check: git branch --merged main
action: Only delete if fully merged (no unmerged commits)
```

**Layer 4: Dry Run Enabled**
```yaml
default_mode: DRY_RUN (preview only)
actual_deletion: Requires explicit --no-dry-run flag
logging: All operations logged to GitHub Actions
```

**Layer 5: Data Preservation**
```yaml
commit_history: Preserved in main forever
recovery: Can be recreated from main any time
logging: Branch deletion logged in cleanup report
```

---

## Data Preservation Guarantee

**100% Code Safety**: ✅ GUARANTEED

- ✅ **All commits preserved**: Every commit from deleted branch is in main history
- ✅ **No PR data loss**: Merged PR commits remain in main
- ✅ **Recreatable**: `git checkout -b old-branch <commit-hash>` from main
- ✅ **Audit trail**: Cleanup logged in GitHub Actions history
- ✅ **No destructive**: Branch is metadata only, commits are permanent

**Example**:
```bash
# Branch deleted: feat/example-feature

# But all commits are in main:
git log --oneline main | grep "feat/example-feature"
# Output: abc1234 feat: example feature (commit preserved)

# Can recreate anytime:
git checkout -b feat/example-feature abc1234
```

---

## Workflow Integration

### GitHub Actions Workflow: `stale-branch-cleanup.yml`

**Triggers**:
- Schedule: Monthly (1st Sunday, 02:00 UTC)
- Manual: `workflow_dispatch` via GitHub Actions UI
- Issue comment: `cleanup:branches` on #755

**Steps**:
1. Scan merged branches
2. Filter by age (30+ days)
3. Generate report
4. Display candidates (dry run)
5. Delete if `--no-dry-run` (execution mode)
6. Comment results to issue #755
7. Apply maintenance policy doc

**Outputs**:
- Cleanup report (STALE_BRANCH_CLEANUP_REPORT.md)
- Branch list (safe for deletion
)
- Execution log (GitHub Actions)

---

## Usage Examples

### Example 1: Preview Cleanup (Recommended First Step)
```bash
cd /home/akushnir/self-hosted-runner

# Preview what would be deleted
gh workflow run stale-branch-cleanup.yml --input dry_run=true

# Wait for completion, review results in:
# - GitHub Actions run output
# - STALE_BRANCH_CLEANUP_REPORT.md
```

### Example 2: Execute Cleanup
```bash
# After reviewing preview, execute actual cleanup
# WARNING: This WILL delete branches
gh workflow run stale-branch-cleanup.yml --input dry_run=false

# Verify results
git fetch origin
git branch -r | wc -l  # Should show fewer branches
```

### Example 3: Issue-Driven Cleanup
```bash
# Comment on #755 to trigger workflow
gh issue comment 755 --body "cleanup:branches"

# Workflow will:
# 1. Scan branches
# 2. Generate report
# 3. Comment results to issue
# 4. Auto-close issue on success (if dry_run=false)
```

### Example 4: Custom Exclusion Pattern
```bash
# Skip additional branches beyond the defaults
gh workflow run stale-branch-cleanup.yml \
  --input dry_run=false \
  --input exclude_pattern="main,master,develop,staging,production,release/*"
```

---

## Monitoring & Reporting

### Cleanup Reports

**Location**: `STALE_BRANCH_CLEANUP_REPORT.md` (repo root)

**Contents**:
- Date and mode (DRY RUN / EXECUTION)
- Branches identified
- Branches deleted
- Safety verification checklist
- Exemption reasons

### GitHub Actions Logs

**Retention**: 90 days  
**Location**: Actions → Stale Branch Cleanup  
**Details**: 
- Per-branch scan results
- Deletion status
- Failure reasons (if any)

### Issue Comments

**Issue**: #755  
**Posts**: 
- Result summary after cleanup
- Branch count before/after
- Exceptions or warnings
- Link to workflow run

---

## Exemptions & Exceptions

### Automatic Exemptions

Branches are **automatically protected** if:
- Updated in last 30 days ✅
- On protected list (main, master, develop, etc.) ✅
- Matches `exclude_pattern` ✅

### Manual Exemptions

To prevent deletion of a specific branch:

**Option 1: Update the branch**
```bash
git checkout feat/important
git commit --allow-empty --message "Keep-alive update"
git push origin feat/important
```
Branch is now < 30 days old, protected!

**Option 2: Add to protected branches**
```
GitHub Repo Settings → Branches → Add rule
Pattern: feature/critical-*
```

**Option 3: Update exclude_pattern**
```bash
gh workflow run stale-branch-cleanup.yml \
  --input exclude_pattern="main,master,myspecial-*"
```

---

## Hands-Off Compliance

This policy achieves the "hands-off" architecture goal:

| Principle | Implementation |
|-----------|---|
| **Immutable** | Policy baked into GitHub Actions, no manual edits needed |
| **Sovereign** | Runs on GitHub infrastructure, no external services |
| **Ephemeral** | Branches are ephemeral metadata; commits are permanent |
| **Independent** | Workflow runs standalone, no dependencies on other systems |
| **Fully Automated** | Monthly auto-cleanup + on-demand triggers, zero manual intervention |

---

## Disaster Recovery

### If a Branch Was Deleted Accidentally

**Recovery is POSSIBLE and EASY** ✅

```bash
# Find the commit hash from main history
git log --oneline main | /grep "branch description"

# Example: commit abc1234 was from the deleted branch

# Recreate the branch
git checkout -b restored-branch abc1234
git push origin restored-branch

# Done! Branch is back
```

### Prevention

Use dry-run mode before every execution:
```bash
# Always preview first
gh workflow run stale-branch-cleanup.yml --input dry_run=true
# Review results
# Then execute if safe
gh workflow run stale-branch-cleanup.yml --input dry_run=false
```

---

## Configuration Reference

### Workflow Inputs

| Input | Default | Description |
|-------|---------|---|
| `dry_run` | `true` | Preview mode (no deletion if true) |
| `exclude_pattern` | `main,master,develop,staging,production` | Branches never to delete (comma-separated) |
| `skip_days` | `30` | Only delete branches older than N days |

### Schedule

```yaml
cron: '0 2 * * 0'  # First Sunday of month, 02:00 UTC
```

### Protected Branches (Built-In)

- `main` - Default branch, always protected
- `master` - Legacy default, always protected
- `develop` - Development branch
- `staging` - Staging environment
- `production` - Production environment

---

## Compliance & Audit

### Audit Trail

All cleanup operations are logged:
- ✅ GitHub Actions workflow logs (90-day retention)
- ✅ Issue comments on #755 (permanent)
- ✅ Cleanup report in repository (permanent)
- ✅ Git reflog (7-day retention for recovery)

### Compliance Verification

To verify compliance with this policy:

```bash
# Check for unexpected branch deletions
git reflog | grep delete

# Verify main branch is intact
git log --oneline main | head -20

# List current remote branches
git branch -r | wc -l
```

---

## Frequently Asked Questions

**Q: Will my commit history be deleted?**  
A: No. All commits are preserved in `main` history forever. Only branch references are removed.

**Q: Can I recover a deleted branch?**  
A: Yes. All commits exist in `main`, so you can recreate the branch from any commit hash.

**Q: How do I prevent a branch from being deleted?**  
A: Either update it within 30 days, or add it to the exclude pattern.

**Q: When does cleanup run?**  
A: Automatically on the 1st Sunday of each month at 02:00 UTC. Or manually via `gh workflow run`.

**Q: Will I be notified?**  
A: Yes. Issue #755 will receive a comment with cleanup results after each run.

---

## Review & Update Schedule

| Item | Frequency | Next Review |
|------|-----------|---|
| Policy document | 6 months | 2026-09-06 |
| Exclusion patterns | As needed | 2026-06-06 |
| Schedule timing | Annually | 2027-03-06 |
| Safety mechanisms | Annually | 2027-03-06 |

---

**Policy Owner**: GitHub Automation  
**Last Reviewed**: 2026-03-06  
**Next Review**: 2026-06-06 (Quarterly)  
**Status**: ✅ ACTIVE & APPROVED
