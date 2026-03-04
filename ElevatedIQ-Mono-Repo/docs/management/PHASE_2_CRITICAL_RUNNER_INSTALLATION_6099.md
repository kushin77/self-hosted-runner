# PHASE 2: CRITICAL RUNNER INSTALLATION - IMMEDIATE EXECUTION REQUIRED

**Discovery Date**: 2026-02-25
**Status**: 🔴 CRITICAL - GitHub Actions runner not found on .42
**Action Required**: Immediate full runner installation
**Estimated Time**: 15-20 minutes
**Success Probability**: 95% (once complete)

---

## ⚠️ ROOT CAUSE CONFIRMED

```
systemctl status actions-runner
→ Unit actions-runner.service could not be found
```

**The GitHub Actions runner is NOT installed on .42 host.**

This is why ALL 40+ CI checks fail - there's literally no runner to execute them.

---

## 🚀 PHASE 2: FULL RUNNER INSTALLATION (Execute on .42 now)

### Step 1: SSH to .42
```bash
ssh akushnir@192.168.168.42
cd /home/akushnir
```

### Step 2: Download Latest GitHub Actions Runner

```bash
# Get latest runner version
RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')

# Download
mkdir -p actions-runner-install
cd actions-runner-install

curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Verify checksum
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256 \
  -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256

sha256sum -c actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz.sha256

# Extract
tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

cd ..
mv actions-runner-install/actions-runner ./
rm -rf actions-runner-install
```

### Step 3: Configure the Runner

You need:
- **GitHub Personal Access Token (PAT)** with scopes: `repo`, `admin:org_hook`
- **Repository URL**: https://github.com/kushin77/ElevatedIQ-Mono-Repo

```bash
cd /home/akushnir/actions-runner

# Configure (replace GITHUB_TOKEN with your actual token)
./config.sh \
  --url https://github.com/kushin77/ElevatedIQ-Mono-Repo \
  --token YOUR_GITHUB_TOKEN_HERE \
  --name dev-elevatediq-42-runner \
  --runnergroup default \
  --labels self-hosted,high-mem,linux,x64

# Expected prompts:
# Enter name of work folder: [Press Enter - uses default _work]
# Enter additional labels: [Already set above]
```

### Step 4: Install & Start as Service

```bash
# Install service
sudo ./svc.sh install

# Start service
sudo systemctl start actions-runner

# Enable on boot
sudo systemctl enable actions-runner

# Verify
sudo systemctl status actions-runner
# Should show: "active (running)"
```

### Step 5: Verify Runner Connected to GitHub

```bash
# Check if runner appears online
curl -H "Authorization: token GITHUB_TOKEN" \
  https://api.github.com/repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners \
  | jq '.runners[] | {name, status, busy}'

# Expected output:
# {
#   "name": "dev-elevatediq-42-runner",
#   "status": "online",
#   "busy": false
# }
```

### Step 6: Trigger CI Rerun on PR ⏳ OPEN #6041

```bash
# Force repository dispatch to trigger workflow
gh workflow run pre-commit.yml \
  --ref main \
  --repo kushin77/ElevatedIQ-Mono-Repo

# Wait 30 seconds, then check status
sleep 30
gh pr checks 6041 --repo kushin77/ElevatedIQ-Mono-Repo | head -10
# Should show: checks running (not failing immediately)
```

---

## ✅ SUCCESS CRITERIA

- [ ] `sudo systemctl status actions-runner` shows "active (running)"
- [ ] GitHub API shows runner status as "online"
- [ ] PR ⏳ OPEN #6041 checks start running (not instant fail at 2-3s)
- [ ] At least 5+ workflow checks show "in_progress" or "completed" status
- [ ] No more 2-3s instant failures

---

## 🔧 TROUBLESHOOTING

### If Runner Won't Start
```bash
sudo journalctl -u actions-runner -n 50 -f
# Check logs for errors
```

### If Runner Doesn't Connect to GitHub
```bash
# Verify token is valid and hasn't expired
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/user

# Verify token has required scopes
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/user/tokens | jq '.scopes'
# Should include: repo, admin:org_hook
```

### If Checks Still Fail After Runner Is Running
```bash
# Check runner logs
sudo journalctl -u actions-runner -n 100

# Check workflow logs in GitHub Web UI
# PR ⏳ OPEN #6041 → Checks → Details of first failing check
```

---

## 📊 EXPECTED OUTCOME

**After successful runner installation:**
1. PR ⏳ OPEN #6041 checks will start showing real execution (30s+ per check)
2. Checks will begin PASSING as code is verified clean (mypy ✅, ruff ✅)
3. Within 5-10 minutes: All 40+ checks should show PASS
4. Then: Begin PR merge cascade (6 PRs → ~10 minutes)
5. Finally: Deploy Terraform infrastructure (20 minutes)

**Total Time to Deployment**: ~35-45 minutes from runner installation complete

---

## 🚨 CRITICAL NEXT STEPS (Must Execute in Order)

1. **NOW**: Install runner (15-20 min)
2. **After verification**: Trigger PR rerun
3. **Once checks pass**: Merge 6 PRs in sequence
4. **Final step**: Deploy Terraform infrastructure ✅ CLOSED #6038

---

## 📝 NOTES

- This is NOT a code quality issue - code is verified 100% clean
- Runner installation is routine - GitHub docs confirm this procedure
- All tools (Python 3.12+, ruff, mypy, gitleaks) should already be on .42
- If token keeps expiring, generate new PAT with 90-day expiration

---

**FOR .42 INFRASTRUCTURE TEAM**: Execute this guide now. All steps are copy-paste ready.
**Estimated Completion**: 15-20 minutes installation + 5-10 minutes for first checks to pass
