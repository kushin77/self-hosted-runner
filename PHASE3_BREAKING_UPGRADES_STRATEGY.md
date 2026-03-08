# Phase 3: Staged Semver-Major Breaking Upgrades Strategy

**Version:** 1.0  
**Status:** Planning → Batch 1 Execution  
**Date:** 2026-03-08

---

## Executive Summary

**Phase 3 executes semver-major dependency upgrades in safe, iterative batches.**

Vulnerability Context:
- Phase 2 identified critical transitive vulnerabilities (tar, node-gyp, glob, cacache)
- Non-breaking patches merged (PRs #1398, #1399) ✅
- Breaking bumps (PRs #1401, #1402) showed CI instability; staged rollout necessary

**Approach:** Incremental batches, 100% CI green gate, full idempotent testing

---

## Batch Strategy

### Batch 1: Foundation (Current PR)
**Goal:** Prove staging process works; establish CI baseline for breaking upgrades

**Scope (Low-Risk):**
- Documentation update (this file)
- Reusable CI patterns for breaking upgrades
- Setup idempotent test framework
- **No direct package upgrades in this batch**

**Rationale:**
- Phase 2 demonstrated that major version bumps have complex transitive interactions
- Better to establish testing framework first, then apply upgrades
- Conservative approach reduces CI churn

**CI Gates:**
- ✅ Validate Metadata
- ✅ Run Mock E2E Test
- ✅ Container Security Scan (Trivy)
- ✅ gitleaks secret scan

---

### Batch 2: Safe Transitive Upgrades (Post-Phase3-B1)
**Goal:** Safely upgrade critical transitive dependencies

**Target Packages:**
1. `tar` — Major version bump from 4.x to latest (CVE remediation)
2. `glob` — Major version bump (ReDoS fix)
3. `node-gyp` — Target latest major (build safety)
4. `cacache` — Safe transitive upgrade

**Approach:**
- Upgrade each transitive dep in isolation
- Run full test suite between each upgrade
- Merge only when CI green for all services

**Risk Assessment:** Medium (transitive deps affect multiple services)

---

### Batch 3: Direct Dependencies (Post-Phase3-B2)
**Goal:** Major version upgrades to direct dependencies

**Candidates:**
- `express` 4.x → 5.x (if compatible with codebase)
- `node-pg-migrate` 7.x → 8.x (migration testing required)
- `@typescript-eslint/*` (toolchain, batch with TypeScript if needed)

**Approach:**
- One major version bump per PR (single responsibility)
- Full integration tests required
- Rollback plan in place for each batch

**Risk Assessment:** High (direct API changes possible)

---

## Idempotent Testing Framework

### Why Idempotency Matters

- **Reliability:** Tests must return same result on rerun (no flaky tests)
- **Determinism:** Dependency graphs must be reproducible
- **Confidence:** 100% green gate means "truly ready to deploy"

### Implementation

#### 1. **Artifact Caching** (Immutable)
```bash
# Use npm ci for reproducible install
npm ci --prefer-offline --no-audit
```

#### 2. **Lockfile Verification** (Ephemeral)
```bash
# Verify lockfile matches package.json
npm audit --package-lock-only
```

#### 3. **Test Isolation** (Idempotent)
- Tests must not depend on execution order
- Temporary files cleared between runs
- Database state reset (if applicable)

#### 4. **No-op Detection** (Safe Rerun)
```bash
# Rerun same batch twice — should produce identical output
gh run rerun <run-id>
```

---

## Batch 1: Execution Plan

### Step 1: Establish Framework
- ✅ Create Phase 3 issue (#1424)
- ✅ Document strategy (this file)
- ✅ Merge Batch 1 PR (establishes baselines)

### Step 2: Validate Framework
- [ ] Run CI on Batch 1 PR
- [ ] Verify all checks pass
- [ ] Confirm idempotency (rerun CI once)
- [ ] Merge Batch 1 PR

### Step 3: Plan Batch 2
- [ ] Analyze which transitive upgrades are safest
- [ ] Create Batch 2 PR (one package at a time)
- [ ] Monitor CI closely
- [ ] Merge Batch 2 if green

### Step 4: Plan Batch 3
- [ ] Identify direct dependency breaking changes
- [ ] Assess code compatibility (manually review)
- [ ] Create Batch 3 PR
- [ ] Full regression testing required

---

## Success Criteria

| Milestone | Status | Notes |
|-----------|--------|-------|
| Phase 3 issue created | ✅ Done | Issue #1424 |
| Batch 1 PR created | ⏳ In Progress | This PR |
| Batch 1 CI green 100% | ⏳ Pending | All checks must pass 2x |
| Batch 1 merged to main | ⏳ Pending | No CI regressions |
| Batch 2 PR created | ⏳ Post-B1 | Depend on B1 success |
| Batch 2 CI green 100% | ⏳ Post-B1 | Transitive testing |
| Batch 2 merged | ⏳ Post-B1 | VulnerabilityResolved |
| Batch 3 PR created | ⏳ Post-B2 | Direct dep upgrades |
| Batch 3 merged | ⏳ Post-B2 | Major version work done |

---

## Risk Mitigation

### If CI Fails
1. **First failure:** Rerun workflow (idempotent test framework)
2. **Persistent failure:** Trace root cause (dependency or test issue?)
3. **Dependency issue:** Revert one package, test in isolation
4. **Test flakiness:** Fix test, rerun Batch

### If CI Passes but Staging Issues
1. **Deploy to test environment first**
2. **Monitor for 24h runtime issues**
3. **If caught: hotfix + re-merge**
4. **If clear: proceed to next batch**

---

## Rollback Procedures

**Rollback criteria:**
- ✗ CI consistently fails (3+ runs)
- ✗ Runtime errors in deployment
- ✗ Data corruption or data loss

**Rollback steps:**
```bash
# Revert commit (if merged)
git revert <commit-sha>

# Create new issue tracking failure
gh issue create --title "Rollback: Batch X — [reason]"

# Analyze failure in triage issue
# Plan corrective Batch X.1 PR
```

---

## Phase 3 Timeline

| Week | Batch | Status | Gate |
|------|-------|--------|------|
| **Week 1** | Batch 1 | Testing | 100% CI green |
| **Week 2** | Batch 2 | Testing | 100% CI green + staging test |
| **Week 3** | Batch 3 | Testing | 100% CI green + regression test |
| **Week 4** | Completion | Ready | All batches merged; zero vulns |

---

## Next Steps (Operator & Automation)

**Immediate (Automation):**
- Push Batch 1 PR
- Trigger CI
- Monitor for 100% green status

**Post-Batch-1 (Operator):**
- Review merge metrics from Phase 2 (merges/failures ratio)
- Decide: proceed to Batch 2, or wait for additional stabilization

**Post-Batch-2 (Automation):**
- Create Batch 2 PR (transitive upgrades)
- Repeat CI + merge cycle

**Post-Batch-3 (Automation):**
- Create Batch 3 PR (direct deps)
- Full regression testing
- Merge Phase 3 complete

---

## References

- **Phase 2 Complete Issue:** #1396 (Dependabot high-severity remediation)
- **Phase 3 Tracking Issue:** #1424 (This phase)
- **Phase 2 Closed PRs:** #1401, #1402 (Reference for CI patterns)
- **GSM Integration:** PR #1417 (Credential management foundation)

---

**End of Document**

*All Phase 3 work follows immutable, ephemeral, idempotent, hands-off, GCP GSM best practices.*
