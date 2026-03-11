# GOVERNANCE ENFORCEMENT DEPLOYMENT GUIDE

**Status:** Ready to Deploy  
**Date:** 2026-03-11  
**Requires:** GITHUB_TOKEN with repo access

## ⚡ Quick Deploy (One Command)

```bash
cd /home/akushnir/self-hosted-runner

# Method 1: With token in environment
export GITHUB_TOKEN="<your-github-token>"
bash infra/deploy-governance-enforcement.sh

# Method 2: Pass token as argument
GITHUB_TOKEN="<your-github-token>" bash infra/deploy-governance-enforcement.sh

# Method 3: From Google Secret Manager (if you have access)
export GITHUB_TOKEN=$(gcloud secrets versions access latest --secret="github-token" --project="nexusshield-prod")
bash infra/deploy-governance-enforcement.sh
```

## 🏗️ What Gets Deployed

### 1. Governance Enforcement Runner
- **File:** `tools/governance-enforcement-run.sh`
- **Purpose:** Execute scanner + post results to GitHub
- **Behavior:** Idempotent (safe to run multiple times)

### 2. Cron Job
- **Schedule:** Daily 03:00 UTC (`0 3 * * *`)
- **Action:** Runs governance enforcement runner automatically
- **Logs:** `/var/log/governance-scan.log` (append-only)

### 3. Deployment Record
- **File:** `governance/GOVERNANCE_ENFORCEMENT_DEPLOYED_<timestamp>.md`
- **Purpose:** Immutable deployment audit trail
- **Contains:** Configuration, deployment timestamp, compliance checklist

## 🎯 Governance Rules Enforced

The deployment uses `tools/governance-scan.sh` which detects:

1. **GitHub Actions Bot Releases** 
   - Detects releases created by `github-actions[bot]` 
   - Reports if found as VIOLATION

2. **PR-Based Releases**
   - Detects releases created via Pull Requests
   - Reports if violations exist

3. **Disallowed Release Creators**
   - Enforces list of allowed humans (if configured)
   - Auto-reports violations

## 📋 Deployment Checklist

- [ ] GITHUB_TOKEN available with `repo` scope
- [ ] User has write access to kushin77/self-hosted-runner
- [ ] Can create cron jobs on this machine (sudo may be needed)
- [ ] `/var/log/` directory writable (or adjust SCAN_LOG path)

## ✅ Post-Deployment Verification

After running deployment, verify:

```bash
# Check cron job installed
crontab -l | grep governance-enforcement

# Check wrapper script exists and is executable
ls -la tools/governance-enforcement-run.sh

# Check deployment record created
ls -la governance/GOVERNANCE_ENFORCEMENT_DEPLOYED_*.md

# View scan logs
cat /var/log/governance-scan.log

# Monitor GitHub issue #2619 for scan results
# (First scan runs at next 03:00 UTC)
```

## 📝 Manual Governance Scan

To trigger scan outside of cron schedule:

```bash
export GITHUB_TOKEN="<your-token>"
export REPO_ROOT="/home/akushnir/self-hosted-runner"
bash tools/governance-enforcement-run.sh
```

## 🔄 Update Token

If GitHub token changes or expires:

```bash
# Update crontab with new token
export NEW_TOKEN="<new-github-token>"
crontab -l | sed 's/GITHUB_TOKEN=.*/GITHUB_TOKEN='"'$NEW_TOKEN'"/  | crontab -
```

## 🚨 Troubleshooting

**Issue:** GITHUB_TOKEN not set
```bash
# Solution: Set token in environment
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
bash infra/deploy-governance-enforcement.sh
```

**Issue:** Permission denied on crontab
```bash
# Solution: Check if you can write to /var/spool/cron/crontabs/
ls -la /var/spool/cron/crontabs/
# If needed, manually add cron entry as admin
```

**Issue:** Scan log permission denied
```bash
# Solution: Use alternate log location
# Edit deploy script to change SCAN_LOG path to writable directory
# Or create /var/log/governance-scan.log with proper permissions:
sudo touch /var/log/governance-scan.log
sudo chmod 666 /var/log/governance-scan.log
```

## 📊 Monitoring

- **GitHub Issue #2619:** All scan results posted as comments (immutable audit trail)
- **GitHub Issue #2623:** Action tracking (closed after deployment)
- **Cron Log:** `/var/log/governance-scan.log` (append-only)
- **Crontab:** `crontab -l | grep governance`

## 🎓 Architecture

```
┌─────────────────────────────────────────┐
│  Daily 03:00 UTC (via cron)             │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ tools/governance-enforcement-run.sh      │
│ - Runs governance-scan.sh               │
│ - Captures violations                   │
│ - Posts results to GitHub               │
│ - Appends to /var/log/governance-scan   │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ GitHub Issue #2619 (append-only)        │
│ - Immutable audit trail                 │
│ - Searchable violation history          │
│ - Permanent record                      │
└─────────────────────────────────────────┘
```

## ✨ Compliance Status

| Requirement | Status | Mechanism |
|-------------|--------|-----------|
| Immutable | ✅ | Append-only logs + GitHub comments |
| Idempotent | ✅ | Scanner safe to re-run; timestamps prevent duplicates |
| Ephemeral | ✅ | Daily execution; no persistent state |
| No-Ops | ✅ | Fully automated via cron |
| Hands-Off | ✅ | Zero manual intervention required |
| No GitHub Actions | ✅ | Uses local cron (not GHA) |
| No PR Releases | ✅ | Scanner detects and reports PR releases |
| Direct Development | ✅ | Enforces direct main commits |

## 🔐 Security Notes

- GITHUB_TOKEN is passed in crontab (crontab readable by user only)
- For enhanced security, consider storing token in Secret Manager and retrieving at runtime
- Log files contain violation details only (no secrets)
- GitHub comment visibility matches issue visibility (public repo = public comments)

## 📞 Support

For issues or questions:
1. Check `/var/log/governance-scan.log` for execution details
2. Review GitHub issue #2619 for violation history
3. Verify cron job: `crontab -l`
4. Test scanner manually: `bash tools/governance-scan.sh`

---

**Ready to deploy?**

```bash
export GITHUB_TOKEN="<your-token>"
bash infra/deploy-governance-enforcement.sh
```
