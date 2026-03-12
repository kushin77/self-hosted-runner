# 🚀 Quick Start Guide - GitHub Issue Automation

## ⚡ 5-Minute Setup

```bash
# 1. Navigate to repo
cd /home/akushnir/self-hosted-runner

# 2. Run one-command setup (creates labels, triages issues, creates examples)
./scripts/github-automation/init-automation.sh kushin77/self-hosted-runner

# 3. Enable workflows (manual - go to GitHub)
# Settings → Actions → General → "Allow all actions and reusable workflows"

# 4. Validate everything works
./scripts/github-automation/validate-automation.sh kushin77/self-hosted-runner

# 5. Try the CLI tool
python3 tools/issue-cli/issue-cli.py list --state open
python3 tools/issue-cli/issue-cli.py velocity --days 7
python3 tools/issue-cli/issue-cli.py sla
```

---

## 📁 Key Files to Know

| File | Purpose | Lines |
|------|---------|-------|
| `GITHUB_ISSUE_AUTOMATION_DEPLOYMENT.md` | **START HERE** - Complete overview | 400 |
| `docs/GITHUB_ISSUE_AUTOMATION_README.md` | User guide with examples | 600 |
| `docs/ISSUE_TAXONOMY.md` | Label reference & governance rules | 400 |
| `scripts/github-automation/README.md` | Script documentation | 300 |
| `.github/workflows/issue-auto-label.yml` | Auto-label & state transitions | 141 |
| `.github/workflows/sla-monitoring.yml` | SLA violation detection | 178 |
| `.github/workflows/dependency-tracking.yml` | Dependency management | 184 |
| `.github/workflows/pr-issue-linking.yml` | PR→Issue correlation | 130 |
| `tools/issue-cli/issue-cli.py` | CLI tool for issue management | 337 |
| `libs/issue-lifecycle/lifecycle.py` | State machine logic | 231 |

---

## 🎯 First-Time Commands

### Setup Everything
```bash
./scripts/github-automation/init-automation.sh kushin77/self-hosted-runner
```

### Create All Labels
```bash
./scripts/github-automation/setup-labels.sh kushin77/self-hosted-runner
```

### Triage Existing Issues
```bash
./scripts/github-automation/triage-issues.sh kushin77/self-hosted-runner
```

### Validate Setup
```bash
./scripts/github-automation/validate-automation.sh kushin77/self-hosted-runner
```

---

## 🚀 Using the CLI Tool

### List Issues
```bash
# All open issues
python3 tools/issue-cli/issue-cli.py list --state open

# By label
python3 tools/issue-cli/issue-cli.py list --label type:bug

# By state
python3 tools/issue-cli/issue-cli.py list --label state:in-progress

# By milestone
python3 tools/issue-cli/issue-cli.py list --milestone "v1.0"
```

### Change Issue State
```bash
# Transition to in-progress
python3 tools/issue-cli/issue-cli.py transition 456 in-progress

# Transition to review
python3 tools/issue-cli/issue-cli.py transition 456 review

# Transition to done
python3 tools/issue-cli/issue-cli.py transition 456 done
```

### Assign Issues
```bash
# Assign to one person
python3 tools/issue-cli/issue-cli.py assign 456 akushnir

# Bulk assign by label
python3 tools/issue-cli/issue-cli.py bulk-assign \
  --map '{"type:security": "akushnir", "type:compliance": "ops-team"}'
```

### Add/Remove Labels
```bash
# Add labels
python3 tools/issue-cli/issue-cli.py label 456 --add priority:p0 sla:breached

# Remove labels
python3 tools/issue-cli/issue-cli.py label 456 --remove stale

# Add and remove
python3 tools/issue-cli/issue-cli.py label 456 --add priority:p1 --remove priority:p2
```

### Generate Reports
```bash
# Team velocity (last 7 days)
python3 tools/issue-cli/issue-cli.py velocity --days 7

# For specific milestone
python3 tools/issue-cli/issue-cli.py velocity --milestone "v1.0" --days 30

# SLA violations
python3 tools/issue-cli/issue-cli.py sla

# Full markdown report
python3 tools/issue-cli/issue-cli.py report --format markdown

# JSON for integration
python3 tools/issue-cli/issue-cli.py report --format json
```

---

## 📝 Creating Issues (Auto-Automation)

### Security Issue (Auto P0)
```bash
gh issue create --repo kushin77/self-hosted-runner \
  --title "SQL injection in search" \
  --label type:security
# → Auto-escalates to P0 + assigned to akushnir
```

### Bug with Severity
```bash
gh issue create --repo kushin77/self-hosted-runner \
  --title "Login redirect fails on mobile" \
  --label type:bug,severity:high,priority:p1
```

### Feature with Dependency
```bash
gh issue create --repo kushin77/self-hosted-runner \
  --title "Add dark mode" \
  --body "Depends on: #456 (theme API)"
# → Auto-marked as blocked, prevents closure until #456 done
```

### Compliance Issue
```bash
gh issue create --repo kushin77/self-hosted-runner \
  --title "SOC2 audit log retention" \
  --label type:compliance
# → Auto P0 + escalated
```

---

## 🔗 PR→Issue Linking

### Auto-Close Issues on PR Merge
```bash
gh pr create --repo kushin77/self-hosted-runner \
  --title "Fix login bug" \
  --body "Closes #456
  
  Changes:
  - Fixed mobile redirect
  - Added tests"
# → #456 transitions to REVIEW immediately
# → When PR merges, #456 auto-closes
```

### Link Without Closing
```bash
gh pr create --repo kushin77/self-hosted-runner \
  --title "Start dark mode UI" \
  --body "Related: #456 (theme API)
  
  This is initial work, not closing #456"
# → #456 stays open, just linked in PR
```

---

## 📊 Automated Reports (After Setup)

These run automatically after workflows are enabled:

**Daily SLA Report** (2 AM UTC)
- Shows violated SLAs
- Auto-escalates security issues
- Marks stale issues

**Daily Velocity** (3 AM UTC)
- Closed issues count
- Bugs vs features
- Average time-to-close

**Weekly Milestone** (Mon 8 AM UTC)
- Release notes from closed issues
- Milestone progress
- Burndown next steps

Access via CLI anytime:
```bash
python3 tools/issue-cli/issue-cli.py sla
python3 tools/issue-cli/issue-cli.py velocity
python3 tools/issue-cli/issue-cli.py report
```

---

## 🏷️ Core Labels to Remember

### States
- `state:backlog` - Not started
- `state:in-progress` - Someone working
- `state:review` - PR submitted
- `state:blocked` - Waiting on dependency
- `state:done` - Complete, pending release

### Types (Auto-detected)
- `type:bug` - Broken
- `type:feature` - New capability
- `type:security` - **Auto P0**
- `type:compliance` - **Auto P0**
- `type:dependencies` - Lib update
- `type:chore` - Refactoring

### Priority
- `priority:p0` - 12h SLA
- `priority:p1` - 3d SLA
- `priority:p2` - 7d SLA
- `priority:p3` - 30d SLA
- `priority:p4` - 90d SLA

### SLA
- `sla:breached` - Time exceeded
- `stale` - 60+ days inactive

---

## 🔄 Issue Lifecycle (Automatic)

```
User creates issue
        ↓
AUTO: Detect type from keywords → Apply type label
AUTO: Detect severity → Apply severity label
AUTO: Apply state:backlog
        ↓
[Assign someone to it]
        ↓
AUTO: Detect → state:in-progress
        ↓
[Person creates PR]
        ↓
AUTO: Parse closes/fixes → Transition → state:review
        ↓
[PR approved and merged]
        ↓
AUTO: Close linked issues → state:done
        ↓
[After 60 days if backlog] → mark stale → auto-close
```

At any point: Auto-escalate if SLA breached or blocked by dependency

---

## 🚨 Troubleshooting

### Workflows not running?
1. Check: Settings → Actions → General
2. Enable: "Allow all actions and reusable workflows"
3. Verify: `.github/workflows/*.yml` files exist
4. Check: Actions tab for error logs

### Labels not applying?
```bash
# Run validation
./scripts/github-automation/validate-automation.sh kushin77/self-hosted-runner

# Check labels exist
gh label list --repo kushin77/self-hosted-runner | grep type:

# Re-run triage
./scripts/github-automation/triage-issues.sh kushin77/self-hosted-runner
```

### CLI not working?
```bash
# Check Python
python3 --version  # Need 3.10+

# Check gh CLI
gh --version

# Authenticate
gh auth login
```

---

## 📚 Full Documentation

- **Deployment Overview:** `GITHUB_ISSUE_AUTOMATION_DEPLOYMENT.md`
- **User Guide:** `docs/GITHUB_ISSUE_AUTOMATION_README.md`
- **Label Reference:** `docs/ISSUE_TAXONOMY.md`
- **Script Docs:** `scripts/github-automation/README.md`
- **CLI Help:** `python3 tools/issue-cli/issue-cli.py --help`

---

## 🎯 What Happens After Setup

### Immediately (within 30 seconds)
- New issues get auto-labeled
- Security issues escalate to P0
- States transition automatically

### Daily (automated)
- SLA violations detected
- Stale issues marked
- Velocity metrics calculated

### Weekly (automated)
- Release notes generated
- Milestone progress reported
- Team burndown charts

### On PR Activity (immediate)
- Issues linked to PRs
- Issues transition through stages
- Issues auto-close on merge

---

## ✨ What Makes This Powerful

1. **Zero Manual Work** - States, labels, SLA all automated
2. **Security First** - 12h response on security issues
3. **Transparency** - Blocked issues visible immediately
4. **Velocity Tracking** - Team metrics automatic
5. **Release Automation** - Notes generated from closed issues
6. **Compliance Ready** - Audit trail via GitHub + JSONL logs

---

## 🎓 Next Steps

1. ✅ Run setup: `./scripts/github-automation/init-automation.sh kushin77/self-hosted-runner`
2. ✅ Enable workflows in GitHub (manual-only step)
3. ✅ Validate: `./scripts/github-automation/validate-automation.sh kushin77/self-hosted-runner`
4. ✅ Create test issue and watch it auto-label
5. ✅ Try CLI: `python3 tools/issue-cli/issue-cli.py velocity --days 7`
6. 📖 Read: `docs/GITHUB_ISSUE_AUTOMATION_README.md`

---

**Status:** ✅ Production Ready (March 12, 2026)  
**Implementation:** Based on ElevatedIQ governance patterns  
**Maintenance:** ~15 min/week for SLA reviews
