# GitHub Issue Automation Framework

Complete automated issue management system inspired by ElevatedIQ's governance patterns.

## ✨ Features

- 🤖 **Automatic state transitions** - Issues flow through backlog → in-progress → review → done
- 🏷️ **Smart labeling** - Auto-detect type, severity, priority from issue content
- 🚨 **SLA enforcement** - Track and escalate breached SLAs (security: 12h, bugs: 1-14d, etc.)
- ⛓️ **Dependency tracking** - Mark blocked issues, prevent closure until dependencies resolved
- 📊 **Velocity reporting** - Track team productivity and metrics
- 🤝 **Kanban automation** - GitHub Projects auto-sync with issue states
- 🔗 **PR linking** - Automatically link and transition issues when PRs are created
- ⏰ **Stale management** - Auto-close inactive backlog items after 60 days
- 📈 **Escalation** - Auto-assign and escalate critical issues

## 📁 Structure

```
.github/
  automation/              # Shared automation utilities
  workflows/
    issue-auto-label.yml              # Auto-label and state transition
    milestone-enforcement.yml         # Milestone policies and release notes
    sla-monitoring.yml               # SLA violation detection
    dependency-tracking.yml          # Dependency graph management
    pr-issue-linking.yml             # Link PRs to issues

libs/
  issue-lifecycle/
    lifecycle.py                     # State machine logic

scripts/github-automation/
  setup-labels.sh                    # Create all GitHub labels
  triage-issues.sh                   # Bulk triage existing issues

tools/issue-cli/
  issue-cli.py                       # CLI tool for issue management

docs/
  ISSUE_TAXONOMY.md                  # Governance rules and label definitions
  GITHUB_ISSUE_AUTOMATION_README.md  # This file
```

## 🚀 Quick Start

### 1. Setup Labels (One-time)

```bash
chmod +x scripts/github-automation/setup-labels.sh
./scripts/github-automation/setup-labels.sh kushin77/self-hosted-runner
```

This creates all 30+ labels with colors and descriptions.

### 2. Enable Workflows

- Go to **Settings → Actions → General**
- Enable **"Allow all actions and reusable workflows"**
- All workflows in `.github/workflows/` are now active

### 3. Triage Existing Issues

```bash
chmod +x scripts/github-automation/triage-issues.sh
./scripts/github-automation/triage-issues.sh kushin77/self-hosted-runner
```

This applies governing labels to all open issues.

### 4. Try the CLI

```bash
python3 tools/issue-cli/issue-cli.py list --state open
python3 tools/issue-cli/issue-cli.py velocity --days 7
python3 tools/issue-cli/issue-cli.py sla
```

## 🤖 Automated Workflows

### Immediate (On Issue Created/Edited)
- ✅ Auto-detect type from keywords (bug, feature, security, etc.)
- ✅ Auto-detect severity for bugs (critical, high, medium, low)
- ✅ Parse dependency patterns (depends on: #123, blocks: #456)
- ✅ Apply state:backlog label
- ✅ Mark blocked issues
- ✅ Auto-assign security/compliance to akushnir

### Scheduled: Daily 2 AM
- 🕐 Check SLA violations
- 🕐 Mark stale issues (60+ days)
- 🕐 Close stale backlog items
- 🕐 Generate SLA violation report

### Scheduled: Daily 3 AM
- 🕐 Clean up labels (remove obsolete ones)
- 🕐 Update milestone progress
- 🕐 Generate velocity metrics

### Scheduled: On PR Created
- 🔗 Parse linked issues (closes #123, fixes #456, refs #789)
- 🔗 Transition issue to state:review
- 🔗 Add comment linking PR to issue

### Scheduled: On PR Merged
- ✅ Close linked issues (closes and fixes patterns)
- ✅ Transition issue to state:done
- ✅ Generate release notes from milestone

## 📊 Issue States

```
┌─────────────┐
│   BACKLOG   │  Default state for new issues
└──────┬──────┘
       │ (assigned without PR)
       ▼
┌──────────────────┐
│  IN_PROGRESS     │  Someone is working on it
└──────┬───────────┘
       │ (PR created)
       ▼
┌──────────────────┐
│     REVIEW       │  PR submitted, awaiting review
└──────┬───────────┘
       │ (approved & merged)
       ▼
┌──────────────────┐
│      DONE        │  Complete, in next release
└──────────────────┘

       Any State
       │ (unresolved dependencies)
       ▼
┌──────────────────┐
│     BLOCKED      │  Waiting on other issue(s)
└──────────────────┘
```

## 🏷️ Key Labels

### State Labels
- `state:backlog` - Not yet started
- `state:in-progress` - Actively being worked on
- `state:review` - PR submitted
- `state:blocked` - Waiting on dependency
- `state:done` - Complete, pending release

### Type Labels (Auto-detected)
- `type:bug` - Something broken
- `type:feature` - New capability
- `type:dependencies` - Dep update
- `type:security` - Security issue (⚠️ P0 forced)
- `type:compliance` - Compliance requirement (⚠️ P0 forced)
- `type:chore` - Refactoring/maintenance

### Priority Labels
- `priority:p0` - Critical (12h SLA)
- `priority:p1` - High (3d SLA)
- `priority:p2` - Medium (7d SLA)
- `priority:p3` - Low (30d SLA)
- `priority:p4` - Minimal (90d SLA)

### SLA Labels
- `sla:breached` - SLA time exceeded
- `sla:critical-1d` - Security issues
- `sla:high-3d` - High priority bugs
- `sla:medium-7d` - Medium priority bugs
- `sla:low-14d` - Low priority bugs

### Relationship Labels
- `blocked-by-issues` - Waits on others
- `blocks-other-issues` - Blocks others
- `duplicate` - Duplicate of another issue
- `related-issue` - Related to another

### Status Labels
- `stale` - No activity 60+ days
- `breaking-change` - Has breaking changes
- `wontfix` - Will not be fixed
- `help-wanted` - Seeking community help

## 📝 Usage Examples

### Create Security Issue (Auto P0)
```bash
gh issue create \
  --title "SQL injection in search query" \
  --body "User input not escaped..." \
  --label type:security
```
→ Automatically assigned P0, escalated to akushnir

### Create Feature with Dependency
```bash
gh issue create \
  --title "Add dark mode UI" \
  --body "Depends on: #456 (API theme endpoint)" \
  --label type:feature,priority:p2
```
→ Automatically marked as `blocked-by-issues`

### Link PR to Multiple Issues
```bash
gh pr create \
  --title "Fix login redirect bug" \
  --body "Closes #789
Fixes #790
Refs #791"
```
→ All three issues transition to `state:review`
→ When PR merges, #789 & #790 auto-close

### Check SLA Status
```bash
python3 tools/issue-cli/issue-cli.py sla
# Output:
# 🚨 SLA Violations (3)
#    #456: security (5d old)
#    #789: bug(critical) (3d old)
#    #990: compliance (2d old)
```

### Generate Team Velocity
```bash
python3 tools/issue-cli/issue-cli.py velocity --days 7
# Output:
# 📊 Velocity Report (Last 7 days)
#    ✅ Total Closed: 23
#    🐛 Bugs: 8
#    ✨ Features: 12
#    ⏱️  Avg Time-to-Close: 2.3 days
```

### List All Blocked Issues
```bash
python3 tools/issue-cli/issue-cli.py list --label blocked-by-issues
# Shows issues waiting on dependencies
```

### Bulk Assign by Label
```bash
python3 tools/issue-cli/issue-cli.py bulk-assign \
  --map '{"type:security": "akushnir", "priority:p0": "ops-team"}'
```

## 📈 Metrics & Reporting

All metrics are available via CLI:

```bash
# Velocity (closed issues per week)
python3 tools/issue-cli/issue-cli.py velocity --days 7 --milestone "v1.0"

# SLA violations
python3 tools/issue-cli/issue-cli.py sla

# Full report
python3 tools/issue-cli/issue-cli.py report --format markdown

# JSON for integration
python3 tools/issue-cli/issue-cli.py report --format json
```

## 🔍 Dependency Parsing

The system recognizes these patterns:

```markdown
# Blocks/depends on
Depends on: #123
Depends on: #123, #124, #125
Blocks: #456
Blocks: #456, #789

# Link to PRs
Closes #789
Fixes #789
Resolves #789
Refs #789
```

## 🛴 Implementation Timeline

- ✅ **Phase 1** (Done): Issue lifecycle state machine
- ✅ **Phase 2** (Done): Auto-labeling workflow
- ✅ **Phase 3** (Done): SLA monitoring & escalation
- ✅ **Phase 4** (Done): Dependency tracking
- ✅ **Phase 5** (Done): CLI tool
- 🔄 **Phase 6** (Coming): GitHub Projects Kanban board integration
- 🔄 **Phase 7** (Coming): Team dashboard with widgets

## 🔧 Troubleshooting

### Workflows not running?
1. Check **Settings → Actions** - enable workflows
2. Verify labels are created: `gh label list --repo <owner/repo>`
3. Check workflow logs: **Actions** tab in GitHub

### Issues not auto-labeling?
1. Run manual triage: `./scripts/github-automation/triage-issues.sh`
2. Check if workflow has permission to edit issues
3. Verify issue has required fields (title, body)

### CLI tool not working?
1. Install Python 3.10+: `python3 --version`
2. Verify gh CLI installed: `gh --version`
3. Authenticate: `gh auth login`

## 📚 Additional Resources

- [Issue Taxonomy](../../docs/ISSUE_TAXONOMY.md) - Complete label definitions
- [Governance Rules](../../docs/ISSUE_TAXONOMY.md#-governance-checks) - Policy details
- [State Machine](../../libs/issue-lifecycle/lifecycle.py) - Implementation

## 🤝 Contributing

All automation can be extended by:
1. Adding new labels to `setup-labels.sh`
2. Creating new workflows in `.github/workflows/`
3. Extending CLI with new commands in `tools/issue-cli/`
4. Updating taxonomy in `docs/ISSUE_TAXONOMY.md`

## 📝 License

Same as parent repository
