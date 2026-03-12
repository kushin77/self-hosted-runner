# GitHub Issue Taxonomy & Governance Framework

## 📋 Issue States (State Machine)

Issues flow through these states automatically:

```
BACKLOG → IN_PROGRESS → REVIEW → DONE
            ↓              ↓
          BLOCKED ←────────┘
```

### State Definitions

| State | Label | Meaning | Triggers |
|-------|-------|---------|----------|
| **Backlog** | `state:backlog` | Not yet started | Default for new issues |
| **In Progress** | `state:in-progress` | Someone is working on it | Assigned + no PR |
| **Review** | `state:review` | PR submitted, awaiting review | PR created or linked |
| **Blocked** | `state:blocked` | Waiting on dependency | Depends-on unresolved |
| **Done** | `state:done` | Complete, waiting for release | PR merged or manually marked |

---

## 🏷️ Issue Type Labels

Auto-detected from issue title/description keywords:

| Type | Label | Keywords | Auto-Escalation |
|------|-------|----------|-----------------|
| **Bug** | `type:bug` | bug, broken, crash, error, fail | Severity-based SLA |
| **Feature** | `type:feature` | add, feat, implement, support, new | Priority-based SLA |
| **Dependencies** | `type:dependencies` | deps, dependencies, update lib | Auto-audit schedule |
| **Chore** | `type:chore` | refactor, cleanup, migrate | P2-default |
| **Security** | `type:security` | security, vuln, cve, auth | **Force P0 + 12h SLA** |
| **Compliance** | `type:compliance` | compliance, audit, cert, soc2 | **Force P0 + 24h SLA** |

---

## 🎯 Priority Levels (MoSCoW)

| Priority | Label | Max Age | Action | Examples |
|----------|-------|---------|--------|----------|
| **P0 (Critical)** | `priority:p0` | 12 hours | Assign immediately, escalate | Production outage, security breach, data loss |
| **P1 (High)** | `priority:p1` | 3 days | Assign to milestone | Major feature, significant bug |
| **P2 (Medium)** | `priority:p2` | 7 days | Sprint planning | Minor feature, small bug |
| **P3 (Low)** | `priority:p3` | 30 days | Backlog | Enhancement, documentation |
| **P4 (Minimal)** | `priority:p4` | 90 days | Community/volunteer | Nice-to-have, future |

---

## 🔴 Severity Levels (for Bugs)

| Severity | SLA | Auto-Label | Examples |
|----------|-----|-----------|----------|
| **Critical** | 1 day | `severity:critical` | System down, data corruption |
| **High** | 3 days | `severity:high` | Major feature broken, important data loss |
| **Medium** | 7 days | `severity:medium` | Partial feature broken, can workaround |
| **Low** | 14 days | `severity:low` | Minor visual bug, cosmetic issue |

---

## ⛓️ Dependency & Relationship Labels

| Label | Meaning | Action |
|-------|---------|--------|
| `blocked-by-issues` | This issue waits on others | Auto-prevents state:done until resolved |
| `blocks-other-issues` | This issue blocks others | Escalates to P0 if blocking P0 issues |
| `related-issue` | Informational link | No action |
| `duplicate` | Same as another issue | Merge and close |

**Trigger Patterns in Description:**
```
Depends on: #123, #456
Blocks: #789
Related: #321
See also: #555
```

---

## 🚨 SLA Enforcement Rules

Auto-applied labels when SLA breached:

| Type | SLA | Breach Label | Escalation |
|------|-----|--------------|-----------|
| `type:security` | 12 hours | `sla:breached` + `priority:urgent` | @akushnir notification |
| `type:bug` + `severity:critical` | 24h | `sla:breached` + `priority:urgent` | Daily report |
| `type:bug` + `severity:high` | 3 days | `sla:breached` | Daily report |
| `type:compliance` | 24h | `sla:breached` | @akushnir + ops team |
| `state:backlog` (60+ days) | 60 days | `stale` | Auto-close (unless P0/P1/security) |

---

## 🤖 Automation Rules

### Auto-Assignment Rules

| Pattern | Auto-Assigned | Notes |
|---------|---------------|-------|
| `type:security` | @akushnir | Always immediate |
| `type:compliance` | @akushnir | Always immediate |
| `priority:p0` | @akushnir | First-response only |
| `type:dependencies` | @akushnir | For vulnerability triage |

### Auto-Transition Rules

| Condition | Action |
|-----------|--------|
| Issue assigned + no PR | → `state:in-progress` |
| PR created + linked | → `state:review` |
| Unresolved dependencies | → `state:blocked` |
| Dependencies resolved | → Previous state (auto-unblock) |
| PR merged + closes ref | → `state:done` |
| 60+ days no activity (non-critical) | → Closed as `not planned` |

### Auto-Labeling Rules

- **Type detection**: Scan title/description for keywords
- **Severity inference**: For bugs, default to "medium" unless specified
- **State tracking**: Add `state:*` to track issue progress
- **Blocking detection**: Parse "depends on" patterns
- **Stale detection**: Add `stale` after 30 days with no updates

### Label Cleanup Rules

Run every night (2 AM):
1. Remove `state:backlog` if issue is assigned
2. Remove `blocked-by-issues` if all dependencies closed
3. Add `stale` if no updates in 30+ days
4. Add `sla:breached` if SLA exceeded

---

## 📊 Automated Reports

### Daily (2 AM UTC)
- SLA violations report (count by type)
- Stale issues needing triage
- Blocked issues status

### Weekly (Monday 8 AM UTC)
- Velocity report (closed by type)
- Burndown progress by milestone
- Dependency graph status

### On Schedule
- Clean up stale labels
- Auto-close stale backlog items (60+ days)
- Release notes from closed milestones

---

## 🔄 Kanban Board Integration

GitHub Projects are auto-synced by issue state:

| Project Column | State | Auto-Move Condition |
|---|---|---|
| Backlog | `state:backlog` | New issue or reset |
| In Progress | `state:in-progress` | Issue assigned |
| In Review | `state:review` | PR created/linked |
| Blocked | `state:blocked` | Unresolved dependencies |
| Done | `state:done` | PR merged |

---

## 📝 Example Issue Descriptions

### Good Bug Report
```markdown
**Description:** Login redirects to 404 on mobile

**Severity:** high
**Priority:** P1

Depends on: #456 (API fix)
Blocks: #789 (release)

Steps:
1. Visit on iPhone
2. Click login
3. See 404
```

### Good Feature Request
```markdown
**Feature:** Add dark mode

**Priority:** P2
**Type:** feature

The UI should support a dark color scheme preference.
```

### Good Security Issue
```markdown
**Security Issue:** SQL injection in search

**Severity:** critical
**Type:** security

User input not escaped in search query...
```

---

## 🎓 Governance Checks

All PRs must:
- [ ] Have milestone assigned
- [ ] Link to issue(s) with `closes #`, `fixes #`, or `refs #`
- [ ] Not violate SLA policies
- [ ] Pass status checks before merge

All issues should:
- [ ] Have type label
- [ ] Have priority label
- [ ] Have milestone (for P0/P1)
- [ ] Not be in backlog for 60+ days without activity

---

## 🔗 Label List (Auto-Created)

### States
- `state:backlog`
- `state:in-progress`
- `state:review`
- `state:blocked`
- `state:done`

### Types
- `type:bug`
- `type:feature`
- `type:dependencies`
- `type:chore`
- `type:security`
- `type:compliance`

### Priority
- `priority:p0`
- `priority:p1`
- `priority:p2`
- `priority:p3`
- `priority:p4`
- `priority:urgent` (SLA breach)

### Severity (Bugs)
- `severity:critical`
- `severity:high`
- `severity:medium`
- `severity:low`

### SLA
- `sla:breached`
- `sla:critical-1d`
- `sla:high-3d`
- `sla:medium-7d`
- `sla:low-14d`

### Relationships
- `blocked-by-issues`
- `blocks-other-issues`
- `duplicate`
- `related-issue`

### Status
- `stale` (60+ days)
- `breaking-change`
- `wontfix`
- `help-wanted`

---

## 🚀 Getting Started

1. **Copy labels to your GitHub repo:**
   ```bash
   ./scripts/github-automation/setup-labels.sh
   ```

2. **Enable workflows:**
   - All `.github/workflows/*.yml` files are active
   - Scheduled runs at 2 AM, 3 AM, 4 AM UTC daily

3. **Use CLI tool:**
   ```bash
   python3 tools/issue-cli/issue-cli.py list --state open
   python3 tools/issue-cli/issue-cli.py velocity --days 7
   python3 tools/issue-cli/issue-cli.py report
   ```

4. **Test on an issue:**
   ```bash
   gh issue create --title "Test: SQL injection in search" \
     --label type:security --body "Test security issue"
   ```
