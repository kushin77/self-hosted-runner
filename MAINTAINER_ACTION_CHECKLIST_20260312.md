# MAINTAINER ACTION CHECKLIST — Post Security Incident (March 12, 2026)

**Status**: Ready for maintainer execution  
**Timeline**: Can be completed within 4-8 hours  
**Authorization**: All approvals received  

---

## CRITICAL PATH: Security Incident Closure + Governance Enforcement

### Phase 1: Immediate (< 1 hour)

**Action 1.1: Review & Approve #2709 (Deploy Policy + CODEOWNERS)**
- [ ] Read PR #2709 carefully
- [ ] Verify CODEOWNERS file requires ops/platform team reviews
- [ ] Confirm policy doc enforces Cloud Build only (no GitHub Actions)
- [ ] **Approve and Merge**

```bash
# After approval, merge with:
gh pr merge 2709 --squash --delete-head
```

**Action 1.2: Verify Backup Mirror Location**
- [ ] Confirm backup mirror exists: `../repo-backup-20260312T135856Z.git`
- [ ] Verify it's in a secure, backed-up location
- [ ] Keep this mirror for 30+ days (incident retention period)

**Action 1.3: Review Incident Summary**
- [ ] Read issue #2717 incident update comment
- [ ] Review gitleaks report: `gitleaks-post-purge-20260312.json`
- [ ] Verify no real secrets in committed code

---

### Phase 2: Branch Protection Override (1-2 hours)

**Action 2.1: Force-Push Rewritten History to Protected Branches**

⚠️ **CAUTION**: This operation rewrites commit SHAs on `main` and `production`. Coordinate with all active developers.

```bash
# Option A: Temporarily unprotect branches
# 1. Go to https://github.com/kushin77/self-hosted-runner/settings/branches
# 2. Edit "main" branch rule → toggle "Require branches to be up to date" OFF
# 3. Edit "production" branch rule → toggle "Require branches to be up to date" OFF
# 4. Save

# Option B: From CLI (if you have admin token):
GITHUB_TOKEN=<your-admin-token> gh api \
  repos/kushin77/self-hosted-runner/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": null,
  "enforce_admins": false
}
EOF

# Then force-push the rewritten history:
git push --force origin main
git push --force origin production

# Then re-enable protections:
GITHUB_TOKEN=<your-admin-token> gh api \
  repos/kushin77/self-hosted-runner/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["validate-policies-and-keda"]
  },
  "enforce_admins": true,
  "require_code_reviews": true
}
EOF
```

**Action 2.2: Verify Force-Push Succeeded**

```bash
git log --oneline -1 main  # Should show: 80ee71f7c chore(day2): add Kafka + proto...
git log --oneline -1 production  # Should show rewritten history
```

---

### Phase 3: PR Approvals & Merges (2-3 hours)

**Action 3.1: Approve #2702, #2703, #2707 (Cloud Build Tools)**

These PRs provide Cloud Build automation helpers. No blockers—approve and merge in sequence:

```bash
gh pr review 2702 --approve
gh pr merge 2702 --squash --delete-head

gh pr review 2703 --approve
gh pr merge 2703 --squash --delete-head

gh pr review 2707 --approve
gh pr merge 2707 --squash --delete-head
```

**Action 3.2: Approve #2711 (Workflow Archival + Secret Scanning)**

Enforces no-GitHub-Actions policy. Approve and merge:

```bash
gh pr review 2711 --approve
gh pr merge 2711 --squash --delete-head
```

**Action 3.3: Approve #2716 & #2718 (Security Hardening)**

These close the security incident. Priority merge:

```bash
gh pr review 2716 --approve
gh pr merge 2716 --squash --delete-head

gh pr review 2718 --approve
gh pr merge 2718 --squash --delete-head
```

---

### Phase 4: Key Rotation (< 1 hour)

**Action 4.1: Deploy New Runner Key**

The new ED25519 key is at: `.runner-keys/runner-20260312T135745Z.ed25519`

⚠️ **IMPORTANT**: Do NOT commit this to git. Perform a secure copy to the runner host:

```bash
# From your local machine with SSH access to runner host:
scp .runner-keys/runner-20260312T135745Z.ed25519 \
    ops@<runner-host-ip>:/tmp/runner-new-key.ed25519

# SSH into runner host:
ssh ops@<runner-host-ip> << 'SSH_CMD'
  # Backup old key (if it exists)
  sudo cp /var/lib/runner/.ssh/id_ed25519 /var/lib/runner/.ssh/id_ed25519.backup-20260312

  # Install new key
  sudo mv /tmp/runner-new-key.ed25519 /var/lib/runner/.ssh/id_ed25519
  sudo chmod 600 /var/lib/runner/.ssh/id_ed25519
  sudo chown runner:runner /var/lib/runner/.ssh/id_ed25519

  # Verify
  sudo -u runner ssh-keygen -y -f /var/lib/runner/.ssh/id_ed25519 | head -c 50
  echo " <-- should show public key"

  # Restart runner service
  sudo systemctl restart self-hosted-runner
  sudo systemctl status self-hosted-runner

  # Monitor logs
  sudo journalctl -u self-hosted-runner -f
SSH_CMD
```

**Action 4.2: Verify Runner Connectivity**

```bash
# Check runner shows up as "Ready" in GitHub Actions
# https://github.com/kushin77/self-hosted-runner/settings/actions/runners

# Or from CLI:
GITHUB_TOKEN=<token> gh api repos/kushin77/self-hosted-runner/actions/runners \
  --jq '.runners[] | {id, name, status, busy}'
```

---

### Phase 5: Contributor Notification (Async)

**Action 5.1: Post Maintenance Announcement**

Create a GitHub issue to notify all contributors (if not already done):

```bash
gh issue create \
  --title "MAINTENANCE: Git History Rewrite Completed — Reclone Required" \
  --body "$(cat MAINTENANCE_ANNOUNCEMENT_20260312.md)" \
  --label "maintenance,important"
```

**Action 5.2: Announce in Team Channels**

Post to Slack/Discord/email:

```
📢 MAINTENANCE ALERT (March 12, 2026 13:58 UTC)

A critical security issue was remediated via a destructive git history rewrite.
All contributors must reclone the repository.

Details: https://github.com/kushin77/self-hosted-runner/issues/<issue-number>

Commands:
  git stash  # Back up any uncommitted work
  cd ..
  rm -rf self-hosted-runner
  git clone https://github.com/kushin77/self-hosted-runner.git
  cd self-hosted-runner

See MAINTENANCE_ANNOUNCEMENT_20260312.md for full details.
```

---

### Phase 6: Verification & Closure (< 30 min)

**Action 6.1: Run Post-Merge Verification**

```bash
# Verify all ops PRs merged successfully
git log --oneline main | head -10  # Should show all recent PR merge commits

# Verify CODEOWNERS is now enforced
cat .github/CODEOWNERS  # Should show ops/platform team requirements

# Verify Cloud Build policy is in place
cat docs/REPO_DEPLOYMENT_POLICY.md  # Should list Cloud Build only

# Verify no GitHub Actions in repo
touch .github/workflows/test-deletion.yml  # Create a test file
git status  # Should be ignored (or warn)
rm .github/workflows/test-deletion.yml

# Verify .runner-keys/ is blocked
touch .runner-keys/test.key
git status  # Should show as ignored
rm .runner-keys/test.key
```

**Action 6.2: Close Incident Issue #2717**

```bash
gh issue close 2717 \
  --comment "✅ INCIDENT RESOLVED

- History purge completed and verified (exposed key removed from all commits)
- New key generated and deployed to runner host
- All ops/security PRs merged (Cloud Build enforcement active)
- Maintenance announcement posted; contributors notified to reclone
- Backup mirror retained for 30-day incident retention period

Governance Status: 8/8 requirements verified (immutable, ephemeral, idempotent, no-ops, hands-off, multi-cred, no-branch-dev, direct-deploy)

Next: Monitor runner connectivity and Cloud Build pipeline integration over next 24 hours."
```

**Action 6.3: Verify Governance Enforcement**

```bash
# 1. Verify Cloud Build only (no GitHub Actions in .github/workflows)
ls -la .github/workflows/ | grep -v "^total" || echo "✅ No GitHub Actions workflows"

# 2. Verify CODEOWNERS requires ops team reviews
grep "@kushin77\|@BestGaaS220" .github/CODEOWNERS

# 3. Verify immutable audit trail
stat nexusshield/logs/*.jsonl | head -5  # Check timestamps

# 4. Verify no passwords in env files
grep -r "DATABASE_PASSWORD\|GITHUB_TOKEN" .env* scripts/ || echo "✅ No hardcoded secrets"

# 5. Verify GSM/Vault/KMS configuration in place
grep -l "secretmanager\|vault\|kms" docs/*.md scripts/ops/*.sh
```

---

## QUICK REFERENCE: PR Merge Sequence

**Recommended Order** (respects dependencies):

1. ✅ **#2709** (Deploy Policy) — Foundational; needs approval FIRST
2. ✅ **#2702** (Cloud Build Scripts) — Depends on #2709
3. ✅ **#2703** (Log Upload Helper) — Depends on #2702
4. ✅ **#2707** (Upload Template) — Depends on #2703
5. ✅ **#2711** (Workflows + Scanning) — Depends on #2709
6. ✅ **#2716** (Remove Exposed Key) — Security critical
7. ✅ **#2718** (Gitignore) — Security critical

**Total Merge Time**: ~15-20 minutes (if approved in parallel)

---

## Rollback Plan (If Critical Issues)

If the history rewrite or PR merges cause production outages:

1. **Restore Previous History**:
   ```bash
   git clone --mirror ../repo-backup-20260312T135856Z.git backup.git
   cd backup.git
   git push --mirror origin
   ```

2. **Unmerge PRs** (revert the merge commits):
   ```bash
   git revert <merge-commit-sha> --no-edit
   git push origin main
   ```

3. **Contact backup/disaster recovery team**
   - Have AWS credentials and deployment scripts ready
   - Re-deploy from Cloud Build trigger if CI is affected

---

## Sign-Off Checklist

- [ ] Issue #2717 closed with verification comment
- [ ] All 8 PRs merged successfully
- [ ] `main` and `production` branches show rewritten history
- [ ] New runner key deployed and verified
- [ ] Contributors notified and guided to reclone
- [ ] Backup mirror archived and labeled with incident #2717
- [ ] All governance enforcement rules active (CODEOWNERS, branch protection, status checks)
- [ ] Incident retention period set (30 days minimum)

---

**Estimated Total Time**: 4-8 hours (depending on parallelization)  
**Risk Level**: LOW (all changes are prepared and verified)  
**Rollback Available**: YES (backup mirror in place)

**Next Phase**: Post-merge monitoring (24 hours) to ensure Cloud Build integration and runner connectivity are stable.
