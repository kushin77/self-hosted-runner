# GitHub Automation Scripts

Collection of scripts for managing GitHub issues and pull requests.

## 🚀 Quick Start

```bash
# One-command setup (recommended)
./init-automation.sh kushin77/self-hosted-runner

# Or setup step-by-step
./setup-labels.sh kushin77/self-hosted-runner
./triage-issues.sh kushin77/self-hosted-runner
./validate-automation.sh kushin77/self-hosted-runner
```

## 📚 Scripts

### `init-automation.sh` - Complete Setup
The master script that sets up everything in one go.

```bash
./init-automation.sh <owner/repo>
```

**What it does:**
1. Creates all 30+ labels with colors and descriptions
2. Lists workflow files to enable manually
3. Triages all existing open issues
4. Creates example test issues
5. Outputs next steps

**When to use:** First-time setup

---

### `setup-labels.sh` - Create GitHub Labels
Creates all issue labels with proper colors and descriptions.

```bash
./setup-labels.sh kushin77/self-hosted-runner
```

**What it does:**
- Creates state labels: `state:backlog`, `state:in-progress`, `state:review`, `state:blocked`, `state:done`
- Creates type labels: `type:bug`, `type:feature`, `type:security`, `type:compliance`, etc.
- Creates priority labels: `priority:p0` through `priority:p4`
- Creates SLA labels: `sla:breached`, `sla:critical-1d`, etc.
- Sets colors for easy visual identification

**When to use:** Fresh repo or after changing label schemes

**Example output:**
```
🏷️ Setting up labels for kushin77/self-hosted-runner...
✓ Created label: state:backlog
✓ Created label: state:in-progress
...
✅ Finished! Created/updated 30 labels
```

---

### `triage-issues.sh` - Bulk Triage Existing Issues
Applies governance labels to all open issues retroactively.

```bash
./triage-issues.sh kushin77/self-hosted-runner
```

**What it does:**
1. Labels unlabeled issues with default `state:backlog`
2. Escalates all `type:security` issues to `priority:p0`
3. Marks issues 60+ days old as `stale`
4. Assigns security/compliance issues to akushnir
5. Shows label distribution summary

**When to use:** 
- After setting up labels
- After enabling automation workflows
- Quarterly to refresh governance

**Example output:**
```
🔍 Triaging issues in kushin77/self-hosted-runner...
Step 1: Labeling unlabeled issues...
  Adding labels to #456...
Step 2: Escalating security issues to P0...
  Setting #789 to P0...
Step 3: Finding stale backlog issues...
  Marking #321 as stale...
✅ Triage complete!

Summary:
{"label": "state:backlog", "count": 245}
{"label": "priority:p2", "count": 180}
...
```

---

### `validate-automation.sh` - Verify Setup
Validates that all automation components are correctly configured.

```bash
./validate-automation.sh kushin77/self-hosted-runner
```

**What it does:**
1. Checks all 5 workflow files exist
2. Verifies 12 required labels are created
3. Tests auto-labeling by creating a test issue
4. Verifies CLI tool is executable
5. Outputs validation summary

**When to use:**
- After initial setup
- Troubleshooting automation failures
- After GitHub settings changes

**Example output:**
```
🔍 Validating issue automation setup...
✓ Checking workflows...
  ✓ issue-auto-label.yml exists
  ✓ milestone-enforcement.yml exists
  ...
✓ Checking labels...
  ✓ state:backlog exists
  ✓ state:in-progress exists
  ...
✓ Checking issue lifecycle...
  ✓ Created test issue #999
  ✓ Auto-labeling works (3 labels applied)
  ✓ Cleaned up test issue

✅ Validation complete!
Next steps:
1. Enable workflows in GitHub Settings → Actions
2. Test CLI: python3 tools/issue-cli/issue-cli.py list --state open
3. Create a test issue and watch it auto-label
```

---

## 🔧 Advanced Usage

### Manual Label Creation (if script fails)

```bash
gh label create "state:backlog" \
  --repo kushin77/self-hosted-runner \
  --color "e2e2e2" \
  --description "Issue in backlog, not yet started"
```

### Triage Only Security Issues

```bash
gh issue list --repo kushin77/self-hosted-runner \
  --state open --label "type:security" --limit 100 | \
  jq -r '.[] | .number' | \
  while read num; do
    gh issue edit "$num" --repo kushin77/self-hosted-runner --add-label "priority:p0"
  done
```

### Export Issues to CSV

```bash
gh issue list --repo kushin77/self-hosted-runner \
  --state open \
  --json number,title,labels,milestone \
  --limit 1000 | \
  jq -r '.[] | [.number, .title, (.labels[].name | join(";")), (.milestone.title // "")] | @csv'
```

### Bulk Close Stale Issues

```bash
gh issue list --repo kushin77/self-hosted-runner \
  --state open --label "stale" --limit 100 | \
  jq -r '.[] | .number' | \
  while read num; do
    gh issue close "$num" --repo kushin77/self-hosted-runner --reason "not planned"
  done
```

---

## 📋 Workflow Integration

After running these scripts, enable workflows in GitHub:

1. Go to **Settings → Actions → General**
2. Select **"Allow all actions and reusable workflows"**
3. Click **Save**

These 5 workflows are now active:
- `issue-auto-label.yml` - Auto-label on issue creation
- `milestone-enforcement.yml` - Enforce milestone policies
- `sla-monitoring.yml` - SLA violation detection
- `dependency-tracking.yml` - Track issue dependencies
- `pr-issue-linking.yml` - Auto-link PRs to issues

---

## 🐛 Troubleshooting

### Scripts won't run (Permission denied)
```bash
chmod +x setup-labels.sh triage-issues.sh validate-automation.sh init-automation.sh
```

### `gh` command not found
Install GitHub CLI: https://cli.github.com

```bash
# macOS
brew install gh

# Linux
sudo apt-get install gh

# Verify
gh --version
```

### Authentication errors
```bash
gh auth login
# Follow prompts to authenticate
```

### Workflows not running
1. Check Settings → Actions → General
2. Verify "Allow all actions" is enabled
3. Check Actions tab for error logs
4. Ensure `.github/workflows/*.yml` files exist

### Labels not being applied
1. Run validate-automation.sh to test
2. Check workflow runs in Actions tab
3. Verify labels exist: `gh label list --repo <owner/repo>`
4. Try running triage-issues.sh again

---

## 📚 Documentation

- [GitHub Issue Automation README](../GITHUB_ISSUE_AUTOMATION_README.md)
- [Issue Taxonomy & Governance](../ISSUE_TAXONOMY.md)
- [Issue CLI Tool](../../tools/issue-cli/issue-cli.py)

---

## 🎯 Usage Patterns

### Pattern 1: Security First
```bash
# Setup and immediately enable security escalation
./init-automation.sh kushin77/self-hosted-runner
# → All security issues auto-escalate to P0
```

### Pattern 2: Retrofit Existing Repo
```bash
# Setup labels first
./setup-labels.sh kushin77/self-hosted-runner
# Wait for manual workflow enablement
# Then triage existing issues
./triage-issues.sh kushin77/self-hosted-runner
```

### Pattern 3: Validation Before Production
```bash
./validate-automation.sh kushin77/self-hosted-runner
# Fix any issues shown
./validate-automation.sh kushin77/self-hosted-runner  # Re-validate
# Deploy to production
```

---

## 🤝 Integration Examples

### With Slack Notifications
Modify `sla-monitoring.yml` to post violations to Slack:
```yaml
- name: Notify SLA breaches
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {"text": "🚨 SLA Breached: ... (see details)"}
```

### With Google Sheets
Use `gh` API + Google Sheets API to log metrics:
```bash
python3 << 'EOF'
# Export metrics to Google Sheets
sh tools/issue-cli/issue-cli.py report --format json | \
  python3 -c "import sys; data = json.load(sys.stdin); ..." # Process and send to Sheets
EOF
```

### With Project Automation
Workflows already sync to GitHub Projects via labels.
Issues with `state:*` labels auto-move between columns.

---

## 📊 Metrics After Setup

After everything is enabled, you'll automatically get:

**Daily Reports:**
- SLA violations (security, bugs, compliance)
- Stale issues (60+ days)
- Velocity metrics

**Weekly Reports:**
- Team throughput (closed issues)
- Milestone progress
- Dependency graph health

Check them via:
```bash
python3 tools/issue-cli/issue-cli.py velocity --days 7
python3 tools/issue-cli/issue-cli.py sla
python3 tools/issue-cli/issue-cli.py report
```

---

## 📝 License

Same as parent repository.
