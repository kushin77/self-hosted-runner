# FAANG-Grade Git Governance Standards

**Status:** ✅ ACTIVE  
**Scope:** All branches, all developers, all automation  
**Enforcement:** Pre-commit hooks + GitHub branch protection rules  
**Review Cycle:** Quarterly policy updates  

---

## 📋 Overview

This document specifies 120+ governance enhancements across 8 critical areas. These standards ensure:

- ✅ Repository integrity and immutability
- ✅ Code quality and safety
- ✅ Audit trail and compliance
- ✅ Developer productivity
- ✅ Incident prevention and recovery

**Compliance is mandatory.** All violations are blocked by pre-commit hooks or branch protection.

---

## 1️⃣ BRANCH MANAGEMENT (20 Enhancements)

### 1.1 Naming Convention

**Pattern:** `TYPE/TICKET-NUMBER-description`

**Mandatory Types:**
- `feature/` - User-facing features
- `fix/` - Bug fixes
- `docs/` - Documentation
- `refactor/` - Code restructuring
- `perf/` - Performance improvements  
- `ci/` - CI/CD pipeline changes
- `test/` - Test additions/fixes
- `chore/` - Maintenance
- `security/` - Security patches

**Validation Rules:**
- Type must match approved list
- Ticket number required (e.g., INFRA-401)
- Lowercase only
- Hyphens not underscores
- Max 50 characters
- No spaces

**Examples:**
```
✅ feature/INFRA-401-oauth2-integration
✅ fix/AUTH-523-session-timeout
✅ docs/improving-readme
✅ security/CVE-2026-0001-sanitize-input

❌ feature (missing ticket)
❌ INFRA-401 (missing type)
❌ feature_oauth (underscore wrong)
❌ feature/infra/401 (wrong format)
```

**Enforcement:** Git pre-push hook validates on every push.

### 1.2 Protected Branches

**Main Branch Protection:**
- Require PR reviews (minimum 1)
- Require status checks passing (all)
- Require branches up-to-date before merge
- Require code owner approval
- Disable force-push (absolute)
- Dismiss stale reviews
- Include administrators in restrictions

**Release Branch Protection:**
- Same as main
- Pattern: `release/v*.x` (e.g., release/v1.2)
- Only hotfix merges allowed
- Tag creation required

**Staging Branch Protection:**
- Require PR reviews
- Status checks must pass
- Code owner approval needed
- Force-push disabled

**Develop Branch Protection:**
- Require PR reviews
- Status checks must pass  
- No force-push

### 1.3 Branch Lifecycle

**Creation:**
```
1. Fetch latest: git fetch origin
2. Create: git checkout -b feature/TICKET-description
3. Push: git push origin feature/TICKET-description
4. Create PR via GitHub UI
```

**Active Development:**
- Commit frequency: At least daily
- Commit size: Logical units (< 500 lines per commit)
- Signing: Optional on feature, required for main merge
- Testing: Local tests before push

**Ready for Review:**
- PR description: Include ticket link + change summary
- Automated checks: All pass (coverage, lint, build)
- Manual review: 1 minimum, 2+ for security/*

**Merge & Cleanup:**
- Merge method: **Squash + merge only** (clean history)
- Delete after merge: Automatic via GitHub setting
- Tag release: Create tag for release branches

**Stale Branch Deletion:**
- Automated: Daily cleanup of branches > 60 days old
- Protected: main, release/*, staging never deleted
- Automatic PR comment before deletion

### 1.4 Release Branches

**Pattern:** `release/v1.2.x` (semantic versioning)

**Rules:**
- Created from main
- No new features (backports only)
- Bug fixes only
- Merged back to main + develop
- Tagged: `v1.2.3` after merge
- Immutable once released

### 1.5 Hotfix Branches

**Pattern:** `hotfix/TICKET-description`

**Rules:**
- Created from main (never develop)
- Critical bugs only (30-min SLA)
- PR merged immediately after review
- Merged back to main + develop + release
- Tagged immediately

---

## 2️⃣ COMMITS (15 Enhancements)

### 2.1 Conventional Commits Format

**Required Format:**
```
type(scope): subject [#TICKET]

body (optional)

footer: issue reference (optional)
```

**Valid Types:**
- `feat` - Feature addition
- `fix` - Bug fix
- `docs` - Documentation
- `refactor` - Code refactoring
- `perf` - Performance optimization
- `test` - Test addition/fix
- `ci` - CI/CD changes
- `chore` - Dependencies/tooling
- `security` - Security fix

**Examples:**
```
✅ feat(auth): add OAuth2 support #1234
✅ fix(api): handle null pointer exception #1235
✅ docs: update installation guide
✅ security: sanitize user input in query parser #1236

❌ added stuff
❌ wip
❌ hotfix asap
❌ random commit message
```

**Enforcement:** Husky pre-commit hook validates.

### 2.2 Commit Size Rules

- **Max lines per commit:** 500 (code changes)
- **Max files per commit:** 10 (related changes only)
- **Min commits per PR:** 1 (squash allowed)
- **Atomic commits:** Each commit must be functional

**Violation handling:**
- Large commits require CODEOWNERS approval
- Pre-commit hook warns at 300 lines
- Blocks at 1000 lines

### 2.3 Commit Signing

**On main/release branches:**
- **REQUIRED:** All commits must be signed
- GPG-signed (gpg -S flag)
- SSH signature accepted
- Verified badge shown on GitHub

**On feature branches:**
- Optional
- Recommended for security/* branches
- No enforcement

**Setup:**
```bash
git config --global user.signingkey YOUR_GPG_KEY
git config --global commit.gpgSign true  # Auto-sign
```

### 2.4 History Immutability

**Rules:**
- No force-push after merge to main
- No rewriting public history
- Revert bad commits, don't erase
- All history preserved for audit

**Blocked Commands:**
- `git push --force` (all branches)
- `git reset --hard` (shared branches)
- `git rebase` (shared branches)
- `git filter-branch` (repository-wide)

**Allowed:**
- `git revert COMMIT` (safe, creates new commit)
- `git reset` (feature branches only before push)
- `git rebase` (feature branches, before first push)

---

## 3️⃣ PULL REQUESTS (25 Enhancements)

### 3.1 PR Requirements

**Mandatory for ALL changes to main:**
- Code review (1 minimum)
- All CI checks passing
- No merge conflicts
- Branch protection rules satisfied

**Cannot be skipped or bypassed.**

### 3.2 PR Size Limits

| Metric | Limit | Enforcement |
|--------|-------|------------|
| Files changed | < 20 | Warning at 15, block at 30 |
| Lines added | < 500 | Warning at 300, block at 1000 |
| Commits | 1-10 | Suggestion to squash |
| Discussion length | Track | Flag if > 10 comments |

**Large Draft issues require:**
- Extra code review (2 minimum)
- Security review (if security code)
- CODEOWNERS explicit approval

### 3.3 PR Template & Description

**Required sections:**
1. **Ticket Reference:** Link to GitHub issue
2. **Summary:** What does this change do?
3. **Testing:** How was it tested?
4. **Breaking Changes:** Any breaking changes?
5. **Screenshots:** If UI changes
6. **Type of Change:** feat/fix/docs/etc

**Template provided:** `.github/pull_request_template.md`

### 3.4 PR Naming

**Format:** `[TICKET] Brief description`

**Valid:**
```
✅ [INFRA-401] Add OAuth2 support
✅ [AUTH-523] Fix session timeout
✅ [DOCS] Update API documentation

❌ WIP
❌ random stuff
❌ fixes
```

### 3.5 Review Requirements

**Code Review:**
- Minimum 1 reviewer (1+ required)
- Review must be thorough (not rubber stamp)
- Comments require author response
- Approval gates merge

**Security Review:**
- Required for security/* branches
- Required for cryptography changes
- Required for authentication/authorization changes
- CODEOWNERS security team must approve

**CODEOWNERS:**
- Maintained in `.github/CODEOWNERS`
- Auto-assigned based on file paths
- Approval is mandatory gate
- 100+ rules configured

### 3.6 Stale PR Management

**Automatic stale PR closing:**
- After 21 days inactive
- Comment with notification
- Allow reopening within 30 days
- Automated workflow runs weekly (Sunday 1 AM UTC)

**Rules:**
- Draft Draft issues ignored
- Draft issues with recent comments not stale
- Ops team can bypass

---

## 4️⃣ MERGE STRATEGIES (12 Enhancements)

### 4.1 Merge Method: Squash + Merge

**Standard:** Always use squash-and-merge to main

**Why:**
- Clean history (one commit per feature)
- Easier reverting
- Simplifies git log
- Prevents mess of developer commits

**Alternatives:**
- `Create a merge commit` - Never (messy)
- `Rebase and merge` - Only on release branches

### 4.2 Merge Commit Messages

**Format:** Must follow Conventional Commits

```
feat(auth): add OAuth2 support (#1234)

- Add OAuth2 OIDC provider
- Support Google and GitHub
- Store tokens in GSM
- Implement automatic refresh

Closes #1234
```

**Requirement:** GitHub squash merge auto-formats this.

### 4.3 Conflict Resolution

**On conflicts:**
1. Author resolves manually
2. Tests must pass
3. Re-request review
4. Cannot auto-resolve
5. No force-merge

**Prevention:**
- Pull main before pushing
- 1-day merge window (auto-close stale)
- Rebase before making PR

### 4.4 Fast-Forward Only

**Rule:** Always fast-forward to main when possible

**Command:**
```bash
git merge --ff-only origin/main  # Explicit FF
```

**When FF not possible:**
- Requires rebase (not merge commit)
- Author responsible for rebase
- Must re-request review after rebase

---

## 5️⃣ CODE REVIEW (15 Enhancements)

### 5.1 Review SLA

| Priority | SLA | Escalation |
|----------|-----|-----------|
| Critical (hotfix) | 30 minutes | Ops notified |
| High (security) | 4 hours | Security team |
| Normal (feature) | 24 hours | Manager |
| Low (docs) | 48 hours | None |

**Escalation:** If not reviewed in SLA, notify manager.

### 5.2 Review Checklist

Reviewers MUST verify:

- [ ] Code solves stated problem
- [ ] No breaking changes undocumented
- [ ] Tests added/updated
- [ ] No hardcoded values/secrets
- [ ] Performance not degraded
- [ ] Error handling present
- [ ] Documentation updated
- [ ] No security vulnerabilities
- [ ] Follows code style guide
- [ ] Uses approved patterns/libraries

### 5.3 Comment Requirements

**Comments must:**
- Be constructive and actionable
- Point to specific lines
- Explain why, not just what
- Suggest solutions when possible

**Blocking comments:**
- Security vulnerabilities
- Breaking changes
- Performance regressions
- Obvious bugs

**Non-blocking comments:**
- Style suggestions
- Refactoring ideas
- Documentation improvements

### 5.4 Approval & Request Changes

**APPROVED:** PR ready to merge
- All concerns addressed
- Code is high quality
- Tests pass

**COMMENT:** Feedback but can merge
- Minor suggestions OK
- Not blocking

**REQUEST CHANGES:** Do not merge
- Must resolve before approval
- Author must respond to each
- Re-review after changes

### 5.5 Expert Routing

**Automatic routing based on expertise:**
- Security/* → Security team
- Infra/* → DevOps team
- Docs/* → Technical writers
- API changes → API team

**CODEOWNERS file:** Enforces routing via GitHub.

---

## 6️⃣ SECURITY & ACCESS (13+ Enhancements)

### 6.1 Secrets Scanning

**Automated scanning:**
- Pre-commit hook (git-secrets)
- GitHub Secret Scanning
- TruffleHog during CI
- All secrets patterns blocked

**Never commit:**
- AWS keys
- Database passwords
- API tokens
- OAuth secrets
- Private keys

**Credential Management:**
- Store in GCP Secret Manager (GSM)
- Rotate every 90 days (automated)
- Access logged
- Principle of minimum access

### 6.2 Force-Push Prevention

**Absolute rule:** Force-push always blocked

**Blocked commands:**
- `git push --force`
- `git push -f`
- `git push --force-with-lease`

**Enforcement:**
- Pre-commit hook rejects
- Branch protection enforces
- No exceptions for admins

**Alternative:** Use `git revert` (safe).

### 6.3 Signed Commits

**Main branch:** Signed required  
**Release branches:** Signed required  
**Feature branches:** Optional but recommended

**Verification:**
- ✅ Verified badge on GitHub
- GitHub enforces on main

**Setup GPG signing:**
```bash
# One-time setup
gpg --gen-key  # Or use existing key
git config user.signingkey KEYID
git config commit.gpgSign true

# Every commit auto-signed now
git commit -m "message"  # Auto-signed
```

### 6.4 CODEOWNERS

**100+ rules enforced:**
- File paths mapped to owners
- Ownership verified per CODEOWNERS file
- Approval gates merge
- Auto-assignment on PR

**Example CODEOWNERS:**
```
# Infrastructure
infra/ @devops-team
terraform/ @infra-leads

# Security
security/ @security-team
*.key @security-team

# API
services/api/ @api-team

# Docs
docs/ @tech-writers
```

### 6.5 2FA & Access Control

**Required for all contributors:**
- GitHub 2FA mandatory
- SSH keys only (no passwords)
- Per-repo deploy keys (no personal keys)
- Quarterly access audit

### 6.6 Branch Protection Rules

**Enforced on main:**
- No direct commits
- Require PR + review
- Require status checks
- No force-push
- Up-to-date before merge
- Admin restrictions apply

---

## 7️⃣ AUTOMATION (10+ Enhancements)

### 7.1 Pre-Commit Hooks

**Installed via Husky:**

| Hook | Purpose | Enforcement |
|------|---------|------------|
| pre-push | Branch name validation | Blocks invalid |
| pre-push | Force-push prevention | Blocks |
| pre-commit | Commit message format | Warns |
| pre-commit | Secrets scanning | Blocks |

**Usage:**
```bash
# Hooks auto-run before push/commit
git commit -m "message"  # Runs pre-commit hooks

# Override (rare, use --no-verify carefully)
git commit --no-verify  # Skips hooks (dangerous!)
```

### 7.2 GitHub Actions Workflows

**Automated tasks:**

| Workflow | Trigger | Action |
|----------|---------|--------|
| credential-rotation.yml | Daily 3 AM UTC | Rotate GSM/VAULT/KMS |
| stale-cleanup.yml | Daily 2 AM UTC | Delete inactive branches |
| stale-pr-cleanup.yml | Weekly Sun 1 AM | Close inactive Draft issues |
| compliance-audit.yml | Daily 4 AM UTC | Check governance compliance |
| release-automation.yml | Push to main | Create release + tag |

**Idempotent design:**
- Safe to run repeatedly
- No duplicate cleanup
- State-aware operations
- Audit logging

### 7.3 CI/CD Gates

**Required checks on main:**
- ✅ Build passes
- ✅ Tests pass (> 80% coverage)
- ✅ Lint passes
- ✅ Security scan passes
- ✅ Secrets scan (no credentials)
- ✅ Deployment preview (if applicable)

**Blocking:** Merge blocked until all pass.

### 7.4 Automated Credential Rotation

**Schedule:** Daily 3 AM UTC

**Rotation:**
- GSM secrets: 90-day cycle
- Vault tokens: 24-hour TTL
- KMS keys: Auto-rotate via AWS

**Multi-layer storage:**
- GSM: Long-lived secrets
- Vault: Dynamic tokens
- KMS: Encryption keys

**Immutable:** All rotations logged, never deleted.

### 7.5 Branch Cleanup Automation

**Schedule:** Daily 2 AM UTC

**Rules:**
- Delete branches > 60 days old
- Never delete protected (main, release/*, staging)
- Generate report
- Send notifications

**Immutable:** Git history preserved before deletion.

### 7.6 PR Stale cleanup

**Schedule:** Weekly Sunday 1 AM UTC

**Rules:**
- Close Draft issues > 21 days inactive
- Leave comment with reason
- Allow reopening
- No auto-deletion (just close)

---

## 8️⃣ DOCUMENTATION (10+ Enhancements)

### 8.1 Change Documentation

**Required for all changes:**
- CHANGELOG.md updated
- Ticket linked
- Breaking changes documented
- Migration guide (if needed)

**Format:**
```markdown
## [1.2.0] - 2026-03-08

### Added
- OAuth2 OIDC provider support (#1234)

### Changed
- API response format (might break clients)

### Fixed
- Session timeout handling (#1235)

### Security
- Sanitized user input in parsers (#1236)
```

### 8.2 Architectural Decisions Record (ADR)

**When to create:**
- Major architecture change
- New pattern/framework adoption
- Significant security decision
- Performance-critical change

**Location:** `docs/adr/`

**Template:**
```
# ADR-001: Use OAuth2 for Authentication

## Status: ACCEPTED

## Context
...

## Decision
...

## Consequences
...

## Alternatives Considered
...
```

### 8.3 Runbooks

**Required for:**
- Deployment procedures
- Emergency response
- Incident recovery
- Common operations

**Location:** `docs/runbooks/`

### 8.4 API Documentation

**Required for all API changes:**
- Endpoint documentation
- Request/response examples
- Error codes documented
- Rate limits specified

**Tools:** OpenAPI/Swagger

### 8.5 README Updates

**Update CONTRIBUTING.md if:**
- Governance changes
- New development setup required
- Testing procedures change

---

## 🎯 Enforcement & Compliance

### Automatic Enforcement

| Rule | Mechanism | Consequence |
|------|-----------|------------|
| Branch naming | Pre-commit hook | Blocks push |
| Force-push | Branch protection | Blocks push |
| Commit signing | GitHub settings | Blocks merge to main |
| PR reviews | GitHub settings | Blocks merge |
| Status checks | GitHub settings | Blocks merge |
| Secret scanning | Pre-commit hook | Blocks commit |
| CODEOWNERS | GitHub settings | Blocks merge |

### Manual Enforcement

- Code reviews (human judgment)
- Security reviews (if needed)
- Performance reviews (if slow)
- Documentation checks

### Violation Response

**Minor violations (style):**
- Comment in PR
- Request change
- Author fixes
- Re-review

**Major violations (security/integrity):**
- Immediately block merge
- Notify security team
- RCA required
- Process update

### Quarterly Policy Review

**Review cycle:** Every Q2/Q4

**Process:**
1. Collect metrics
2. Identify pain points
3. Propose changes
4. Team discussion
5. Update documents
6. Re-deploy enforcement
7. Team training

---

## 📊 Metrics & Monitoring

**Track monthly:**
- Merge time to main
- PR size trends
- Review SLA compliance
- Branch protection violations
- Stale branch cleanup rate
- Credential rotation success
- CI/CD pass rate
- Security issue detection

**Success targets:**
- Merge time < 24 hours
- PR size < 400 lines
- Review SLA 100%
- Zero branch protection bypasses
- 90%+ stale cleanup
- 100% credential rotation
- 95%+ CI pass rate

---

## 📚 Quick Reference

### Checklist for Developers

Before creating PR:
- [ ] Branch name valid (feature/TICKET)
- [ ] Commits follow format
- [ ] Tests added/passing
- [ ] No secrets/credentials  
- [ ] Documentation updated
- [ ] Signed locally (on main)
- [ ] Pull latest from origin

Before pushing:
- [ ] Verified all above
- [ ] PR description complete
- [ ] Requested reviewers
- [ ] Linked ticket

Before merging:
- [ ] All reviews approved
- [ ] All CI checks pass
- [ ] No merge conflicts
- [ ] Branch up-to-date
- [ ] Ready for squash-merge

### Common Issues & Solutions

**"Force-push rejected"**
- Why: Branch protection
- Solution: Use `git revert` instead

**"Merge blocked - status checks failing"**
- Why: CI didn't pass
- Solution: Fix code, run tests locally, push again

**"Branch protection - require signed commits"**
- Why: Unsigned commit to main
- Solution: Setup GPG signing, re-commit

**"PR stale after 21 days"**
- Why: Inactive PR
- Solution: Reopen PR, request review, or close if done

**"Terrible commit message"**
- Why: Doesn't follow format
- Solution: Amendment: `git commit --amend`

---

## ✅ Approval Checklist (For Admins)

- [ ] All 120+ enhancements listed
- [ ] Enforcement mechanisms enabled
- [ ] Pre-commit hooks deployed  
- [ ] Branch protection configured
- [ ] CODEOWNERS verified
- [ ] GitHub Actions active
- [ ] Team trained
- [ ] Documentation complete
- [ ] Metrics being tracked
- [ ] Quarterly review scheduled

---

**Version:** 1.0-FINAL  
**Status:** ✅ ACTIVE  
**Effective Date:** 2026-03-08  
**Last Updated:** 2026-03-08  
**Enforcement:** MANDATORY  
**Review Cycle:** Q2 & Q4 (quarterly updates)
