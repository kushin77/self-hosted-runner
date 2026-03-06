# Branch Cleanup Policy

## Purpose
This document establishes a maintenance policy for keeping the repository clean by removing merged feature branches that are no longer needed.

## Frequency
- **Automatic**: Merged branches are cleaned up after each release cycle
- **Manual**: Run every 2 weeks via scheduled GitHub Actions workflow
- **On-Demand**: Can be triggered with `maint:cleanup-branches` comment on issues

## Scope

### Delete (Merged & No Longer Needed)
```
feat/minio-artifacts         - MinIO integration complete
feat/minio-validate          - Validation implemented
feat/pipeline-repair-*       - Pipeline repair features merged
feat/ci-repair-*             - CI repair features merged
feat/deploy-rotation-*       - Rotation automation merged
feat/harbor-*                - Harbor integration merged
feat/auto-provision-*        - AppRole provisioning merged
feat/ansible-*               - Ansible improvements merged
feat/observability-*         - Observability features merged
```

### Keep (Active Development)
- `main` - Production branch
- `develop` - Development branch (if maintained)
- Branches with open PRs
- Recent branches (<1 week old)

## Cleanup Workflow

**Automated via GitHub Actions**:
```yaml
name: Branch Cleanup
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly Sunday
  workflow_dispatch:
jobs:
  cleanup:
    - List merged feature branches
    - Delete from remote
    - Create commit documenting removed branches
    - Post summary to GitHub issues
```

## Safety Measures

1. **Fetch latest**: Always fetch before checking merge status
2. **Verify main**: Confirm branch is merged to main before deletion
3. **Backup**: Create commit log of deleted branches
4. **Notification**: Post summary of cleanups to team
5. **Reversible**: All deletions documented in git history

## How to Trigger

### Option 1: GitHub Actions
```
Go to Actions → Branch Cleanup → Run workflow
```

### Option 2: Issue Comment
```
Comment anywhere: maint:cleanup-branches
Workflow starts automatically
```

## Excluded Patterns

Never delete:
- `main`, `master`, `develop`, `staging`, `production`
- `release/`, `hotfix/`, `bugfix/` branches
- Branches with open PRs
- Branches updated in last 7 days

## Compliance

- ✅ **Immutable**: All deletions logged in git commits
- ✅ **Sovereign**: Self-service cleanup via automation
- ✅ **Ephemeral**: No persistent branch state
- ✅ **Independent**: No external coordination needed
- ✅ **Fully Automated**: Hands-off implementation

## References

- [GitHub branch cleanup automation](/github/workflows/branch-cleanup.yml)
- Issue #755: Branch cleanup proposal

---
*Policy established: 2026-03-06*  
*Maintenance: Automated weekly cleanup active*
