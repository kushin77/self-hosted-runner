---
title: CI/CD Automation & PR Strategy — Hands-Off Governance
version: 1.0
date: 2026-03-07
status: Production Ready
---

# CI/CD Automation & PR Strategy — Hands-Off Governance

## 🎯 Overview

This document describes the **immutable, hands-off continuous integration and Draft issue governance** system used in the self-hosted runner infrastructure. All code changes flow through an automated pipeline that ensures compliance, security, and operational readiness.

---

## 🔄 Workflow: From Code to Deployment

### 1. Developer Creates PR

```bash
git checkout -b feature/my-change
# ... make changes ...
git commit -m "feat: Add new feature"
git push origin feature/my-change
gh pr create --title "feat: Add new feature" --body "Description"
```

### 2. Automated Checks Run (Pre-Merge)

Upon PR creation, GitHub Actions automatically runs:

| Check | Workflow | Purpose | Requirement |
|-------|----------|---------|-------------|
| **Preflight** | `.github/workflows/preflight.yml` | Validates YAML syntax, file checksums | ✅ Must Pass |
| **Gitleaks** | `.github/workflows/security-audit.yml` | Scans for secrets/credentials | ✅ Must Pass |
| **Sequencing Audit** | `.github/workflows/workflow-sequencing-audit.yml` | Verifies safeguards in workflows | ✅ Must Pass |
| **Alerts** | `.github/workflows/slack-notifications.yml` | Posts to Slack (informational) | ⭕ Notify Only |

**Status Check Config:**
- Branch protection rule requires all status checks to pass before merge
- Dismissal of stale reviews: Enabled (ensures fresh reviews on new commits)

### 3. Manual Review (Optional)

```bash
# Maintainer reviews the PR
gh pr view <pr-number> --web  # Opens PR in browser

# Add review comments if needed
gh pr comment <pr-number> --body "Great work! Minor suggestion on line XX"

# Approve PR (or request changes)
gh pr review <pr-number> --approve
```

### 4. Auto-Merge on Green

Once all checks pass and (optionally) approval is received:

```bash
# Auto-merge strategy: Squash all commits into one
# This happens automatically when:
# - All status checks ✅ pass
# - Branch is up-to-date with base branch (main)
# - No blocking review comments

# Logs are sent to Slack:
# "🟢 PR #1234 auto-merged to main (squash commit: abc1234)"
```

**Why Squash?**
- ✅ Clean, linear history (one commit per feature)
- ✅ Easier to revert if needed (revert one commit, not many)
- ✅ Better for release notes and changelog
- ✅ Simplifies bisecting for bug hunting

### 5. Post-Merge Automation (CD Pipeline)

After merge to main:

```
┌──────────────────────────────────────┐
│ PR Merged to Main (Commit: abc1234)  │
├──────────────────────────────────────┤
│                                      │
│ [TRIGGER] push to main branch        │
│    ↓                                 │
│ [security-audit.yml] runs            │
│    ↓                                 │
│ [Scan with Gitleaks + Trivy]        │
│    ↓                                 │
│ [Results posted to Issues]           │
│    ↓                                 │
│ [Slack alert if vulns found]        │
│    ↓                                 │
│ [Deployment workflows may trigger]   │
│    ↓                                 │
│ [System fully operational]           │
└──────────────────────────────────────┘
```

---

## 📋 Status Checks Explained

### Preflight Check

**Purpose:** Validate all YAML files and scripts before execution

**What it checks:**
- ✅ `.github/workflows/*.yml` — Valid GitHub Actions YAML
- ✅ `.github/actions/*/action.yml` — Valid composite action YAML
- ✅ `ansible/**/*.yml` — Valid Ansible playbook YAML
- ✅ `scripts/*.sh` — Valid shell scripts (syntax check)
- ✅ File encoding (UTF-8, no malformed bytes)

**Failure Mode:**
```bash
# If preflight fails:
>> Error: .github/workflows/my-workflow.yml has invalid YAML
>> Line 25: Expected mapping, found scalar

# Fix: Correct the YAML and push again
# PR will automatically re-run checks
```

### Gitleaks Security Scan

**Purpose:** Detect secrets, credentials, API keys, PII in code

**What it scans for:**
- ✅ AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
- ✅ GCP service account keys
- ✅ GitHub tokens and PATs
- ✅ Private SSH keys
- ✅ Database passwords
- ✅ API keys (Slack, SendGrid, etc.)

**Failure Mode:**
```bash
# If Gitleaks finds a potential secret:
>> ⚠️ Potential secret detected: line 42 (rule: "AWS Key")
>> File: config/credentials.yaml

# Fix: Remove the secret, commit with --amend, force-push
git rm config/credentials.yaml
git add .
git commit --amend --no-edit
git push --force-with-lease
```

**False Positives:**
If you get a false positive (e.g., "V1234567890" looks like an API key but isn't):
```bash
# Add an exception to .gitignore-secrets
echo "V1234567890" >> .gitignore-secrets
git add .gitignore-secrets && git commit -m "chore: Add gitleaks false positive exception"
```

### Workflow Sequencing Audit

**Purpose:** Ensure workflows have correct safeguards (concurrency, cancel-in-progress, environment protections)

**What it audits:**
- ✅ All workflows have `concurrency` defined
- ✅ Deployment workflows have `environment:` + approval rules
- ✅ Sensitive operations protected by `if:` conditions
- ✅ No workflows can override branch protections

**Failure Mode:**
```bash
# If audit fails:
>> Workflow run-deploy.yml missing concurrency safeguard
>> Add: concurrency: group/deploy/${{ github.ref }}

# Fix: Add safeguards and re-push
```

---

## 🚀 Deployment Pipeline (CD)

### Automatic Deployment Triggers

After code merges to `main`:

```bash
# Immediately triggered:
1. security-audit.yml
   - Scans repository for vulnerabilities
   - Duration: ~2-5 minutes
   - Failure: Posts findings to security issues

2. Workflow lint checks
   - Re-validates all workflows one more time
   - Duration: ~30 seconds
   - Failure: Blocks deployment (requires PR fix)

# Conditionally triggered:
3. Deployment workflows (if safe)
   - dr-smoke-test.yml (on main)
   - verify-secrets-and-diagnose.yml (if secrets available)
   - Duration: ~5-10 minutes each
```

### Deployment Failure Recovery

If a post-merge workflow fails:

```bash
# 1. Investigate via issue comments
gh issue list --labels "deployment-failure" --state open

# 2. Create a hotfix PR
git checkout -b hotfix/deployment-issue
# ... fix the issue ...
git push origin hotfix/deployment-issue
gh pr create --title "hotfix: Fix deployment issue #XXXX"

# 3. Auto-merge process repeats
# Once checks pass, PR merges automatically
```

---

## 🔒 Branch Protection Rules

**Main Branch Protection:**

| Rule | Setting | Purpose |
|------|---------|---------|
| Require Draft issues | ✅ Yes | All changes require review |
| Require status checks | ✅ Yes | Preflight, Gitleaks, Audit must pass |
| Require branch to be up to date | ✅ Yes | Must sync with latest main before merge |
| Require code review | ⭕ No* | Can auto-merge without review (if checks pass) |
| Restrict who can force push | ✅ Admin Only | Prevents accidental overwrites |
| Auto-delete head branches | ✅ Yes | Clean up merged Draft issues |

*Can be configured to require 1+ review if desired

---

## 📊 Monitoring & Dashboards

### View All Recent Merge Activity

```bash
# Last 20 commits to main (all merged Draft issues)
gh api repos/kushin77/self-hosted-runner/commits?sha=main&per_page=20 \
  --jq '.[] | {message: .commit.message, author: .commit.author.name, date: .commit.author.date}'

# Or via git
git log main --oneline -20
```

### Track PR Metrics

```bash
# Average time from PR open to merge
gh pr list --state closed --repo kushin77/self-hosted-runner --limit 50 \
  --json number,createdAt,mergedAt,title

# Count of auto-merged vs manually merged
gh api repos/kushin77/self-hosted-runner/pulls?state=closed&per_page=100 \
  --jq '.[] | {number, mergedBy: .merged_by.login}' | sort | uniq -c
```

### Check Workflow Health

```bash
# View all workflows and their status
gh workflow list --repo kushin77/self-hosted-runner

# Get last 5 runs of a workflow
gh run list --workflow preflight.yml --repo kushin77/self-hosted-runner --limit 5

# Detailed status of a single run
gh run view <run-id> --repo kushin77/self-hosted-runner
```

---

## 🛠️ Common Scenarios

### Scenario 1: "My PR is stuck, checks are still running"

**Diagnosis:**
```bash
gh run list --repo kushin77/self-hosted-runner --limit 5 --json status
# If status is "QUEUED", runners may be busy
```

**Action:**
- ✅ Check GitHub Status (https://www.githubstatus.com)
- ✅ Wait 5-10 minutes for queue to clear
- ✅ If still stuck after 15 min, ping a maintainer

### Scenario 2: "Preflight check failed with YAML error"

**Diagnosis:**
```bash
gh run view <run-id> --repo kushin77/self-hosted-runner --log | grep "Error\|error"
```

**Action:**
1. Find the offending file and line number
2. Fix the YAML syntax:
   ```bash
   yamllint path/to/file.yml  # Shows errors
   vi path/to/file.yml         # Edit it
   ```
3. Commit and push:
   ```bash
   git add path/to/file.yml
   git commit -m "fix: Correct YAML syntax"
   git push
   ```
4. PR checks automatically re-run

### Scenario 3: "Gitleaks failed: false positive"

**Diagnosis:**
```bash
gh run view <run-id> --repo kushin77/self-hosted-runner --log | grep "Potential secret"
```

**Action:**
1. Verify it's actually a false positive (e.g., hardcoded example value)
2. Add exception:
   ```bash
   echo "my-false-positive-string" >> .gitignore-secrets
   git add .gitignore-secrets
   git commit -m "chore: Add gitleaks false positive exemption"
   git push
   ```
3. PR checks automatically re-run

### Scenario 4: "I need to force-merge despite check failures"

**Important:** This is **not recommended** (breaks automation safeguards), but if absolutely necessary:

```bash
# Only available to admins
# Go to GitHub UI → PR → "Merge without waiting for checks"

# Or via CLI (requires admin role)
gh pr merge <pr-number> --admin --squash --repo kushin77/self-hosted-runner
```

**⚠️ Use sparingly — bypassing checks can introduce bugs/security issues**

---

## 📈 Best Practices

### For PR Authors

- ✅ **Keep Draft issues focused:** One feature or fix per PR
- ✅ **Write clear commit messages:** `feat:`, `fix:`, `docs:`, `chore:` prefixes
- ✅ **Reference related issues:** Use `Closes #1234` in PR body
- ✅ **Run checks locally first:** `yamllint`, `shellcheck`, etc.
- ✅ **No hardcoded secrets:** Always use GitHub secrets

### For Reviewers

- ✅ **Review for logic, not style:** Automated checks handle syntax
- ✅ **Approve promptly:** System auto-merges after approval + checks
- ✅ **Leave constructive comments:** Help authors learn
- ✅ **Don't block for trivial issues:** Use suggestions instead of request changes

### For Maintainers

- ✅ **Monitor failed checks:** Investigate and fix root causes
- ✅ **Update protected branches:** Adjust rules if automation changes
- ✅ **Rotate secrets regularly:** Update GitHub secrets per policy
- ✅ **Document exceptions:** Keep `.gitignore-secrets` current

---

## 🔐 Governance Principles

This CI/CD system embodies **hands-off automation** principles:

| Principle | How We Apply It |
|-----------|-----------------|
| **Immutable** | All workflow changes tracked in Git; no manual runner modifications |
| **Ephemeral** | Each workflow run uses fresh containers; no persistent state |
| **Idempotent** | Workflows safe to re-run; same result each time |
| **Noop-Safe** | Multiple PR checks don't cascade or conflict; reads-only by default |
| **Fully Automated** | After PR creation, zero human intervention until merge (if checks pass) |

---

## 📚 Related Documentation

- [Deploy Key Remediation Runbook](DEPLOY_KEY_REMEDIATION_RUNBOOK.md)
- [Hands-Off Operator Playbook](HANDS_OFF_OPERATOR_PLAYBOOK.md)
- [GitHub Actions Docs](https://docs.github.com/en/actions)
- [Branch Protection Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)

---

## 📞 Support

For issues with:
- **PR checks:** Comment on the PR with `@github-actions: re-run`
- **Workflow failures:** Open an issue with the run ID: `gh run view <run-id>`
- **Merge conflicts:** Rebase: `git rebase main && git push --force-with-lease`

---

**Last Updated**: 2026-03-07  
**Version**: 1.0 (Production Ready)  
**Maintainer**: Automation Team
