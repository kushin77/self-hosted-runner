# Phase 3 Operations Runbook

**Last Updated:** March 6, 2026, 23:30 UTC  
**Status:** HANDS-OFF READY  
**Primary Contact:** Ops Team (Issue #900)

---

## Overview

This runbook guides operations teams through the final credential restoration step and validates the complete hands-off CI/CD automation is operational.

---

## Pre-Restoration Checklist

✅ All PRs merged to main:
- PR #862: e2e runner-discovery + hosted-fallback
- PR #866: MinIO credentials in reusable callables
- PR #868: portal-sync MinIO upload
- PR #872: auto-trigger legacy cleanup

✅ Legacy infrastructure cleanup completed successfully (Issue #787 CLOSED)

✅ All tracking issues updated (Issues #893 CLOSED, #900/#901 OPEN, #909 OPEN)

✅ Immutable documentation committed to repo

---

## Required Action: Docker Registry Secret Restoration

### Step 1: Access Repository Settings
1. Navigate to: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions
2. Ensure authenticated as a user with Admin or Maintainer rights

### Step 2: Add/Restore Three Secrets

Create or update these three secrets:

**Secret 1: REGISTRY_HOST**
- Name: `REGISTRY_HOST`
- Value: [Your Docker registry hostname, e.g., registry.example.com]
- Save

**Secret 2: REGISTRY_USERNAME**
- Name: `REGISTRY_USERNAME`
- Value: [Docker registry username]
- Save

**Secret 3: REGISTRY_PASSWORD**
- Name: `REGISTRY_PASSWORD`
- Value: [Docker registry password/token]
- Save

### Step 3: Verify Secrets are Active
1. In the Actions Secrets panel, confirm all three secrets are listed and show "Updated X minutes ago"
2. Do NOT attempt to view/copy the values (GitHub will not display them)

---

## Post-Restoration Automation Flow

### Automatic Step 1: CI Trigger (2-5 minutes)
Once secrets are saved, GitHub will automatically trigger:
1. Next scheduled CI workflow run (or manual trigger)
2. CI-images build-and-push workflow will succeed (no longer blocked by missing creds)
3. Workflow run logs will show successful push to registry

### Automatic Step 2: E2E Tests (5-15 minutes)
Once build-and-push succeeds:
1. E2E test workflow auto-triggers (if configured)
2. Tests run against container images in registry
3. Results reported to PR checks

### Automatic Step 3: Repository Ready (15-30 minutes)
Upon E2E success:
1. All PR checks turn green
2. Branch protection requirements satisfied
3. Repository fully operational for development

---

## Validation Checklist (Post-Restoration)

After restoring secrets, verify progression:

- [ ] **5 mins:** Check Actions tab for active CI-images run
  - Expected: Status = "In Progress" or "Completed"
  
- [ ] **10 mins:** Verify build-and-push completion
  - Expected: Run conclusion = "success"
  - Navigate to: Workflow → Latest run → View logs
  
- [ ] **15 mins:** Check for E2E test run (if configured)
  - Expected: New test workflow run appears in Actions
  
- [ ] **20 mins:** Verify E2E results
  - Expected: Test suite conclusion = "success"
  
- [ ] **30 mins:** Confirm production readiness
  - Expected: All required checks passing on main
  - Expected: Repository dashboard shows ✅ all checks

---

## Troubleshooting

### Issue: CI-images still failing after secret restoration
**Diagnosis:**
1. Go to Actions → Latest CI-images run → Build & Push step
2. Check for errors in the step logs

**Likely causes:**
- Secrets not properly saved (try re-entering)
- Wrong secret names (must be exactly: REGISTRY_HOST, REGISTRY_USERNAME, REGISTRY_PASSWORD)
- Credential values incorrect
- Registry endpoint unavailable

**Resolution:**
1. Re-verify all three secrets in Settings → Secrets
2. Check registry endpoint connectivity from GitHub Actions
3. Post diagnostic output to Issue #900; Ops on-call will assist

### Issue: Secrets saved but CI still says "missing credentials"
**Diagnosis:**
Secrets cached in workflow; need to trigger new run

**Resolution:**
1. Go to Actions tab
2. Click "Re-run all jobs" on the most recent CI run
3. CI will now pick up the restored secrets

---

## Success Criteria

Repository will be deemed **FULLY OPERATIONAL** when:

✅ Issue #900 confirmation comment posted (Ops confirms secrets restored)

✅ Latest CI-images workflow run shows conclusion = "success"

✅ Latest E2E test run (if configured) shows conclusion = "success"

✅ All required branch protection checks passing on main branch

✅ Team can merge PRs without manual CI approval

---

## Post-Success Documentation

Once all success criteria met:

1. **Update Issue #900:** Post final confirmation comment; request closure
2. **Close Issue #900:** Mark as complete once confirmed
3. **Update Issue #909:** Post success summary
4. **Repository Status:** System is now fully hands-off CI/CD enabled

---

## Ongoing Operations

With Phase 3 automation active:

### Automated Events
- New code commits trigger CI automatically
- Failed checks block merges (branch protection)
- Successful checks enable merges
- E2E tests run on all relevant PRs

### Manual Events (Ops)
- Monitor irregular CI failures (post to issues)
- Alert if registry connectivity issues arise
- Maintain credential freshness (rotate every 90 days)

### Development Team
- Push code; automation handles rest
- Monitor PR checks for green status
- Merge when all checks pass (no manual trigger needed)

---

## Emergency Procedures

### If Registry Becomes Unavailable
1. Comment on Issue #900 with status
2. Ops team investigates registry health
3. Temporary fallback (PR #886) prevents CI from failing on registry push
4. Once fixed, issue comment reopens Issue #900 for re-validation

### If Secrets Expire
1. Ops restores new credentials to same secret names
2. Update only the secret `Value` field
3. No code changes needed; CI automatically uses new secrets

---

## Contact & Escalation

**Primary:** Ops Team / Issue #900  
**Escalation:** Project maintainers / Issue #909  
**Emergency:** Project lead or on-call DevOps engineer

---

## Document Control

**Version:** 1.0  
**Last Reviewed:** March 6, 2026  
**Next Review:** August 6, 2026 (6 months)  
**Immutable:** This document is committed to git; changes require pull request

---
