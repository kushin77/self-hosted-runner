# Hands-Off Automation System Runbook

**Status**: ✅ **FULLY OPERATIONAL** | Date: March 7, 2026 | Mode: Immutable, Ephemeral, Idempotent, Hands-Off

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Automation Workflows](#automation-workflows)
3. [Issue Lifecycle Management](#issue-lifecycle-management)
4. [Secrets Management](#secrets-management)
5. [Monitoring & Alerts](#monitoring--alerts)
6. [Emergency Procedures](#emergency-procedures)
7. [Troubleshooting](#troubleshooting)
8. [Adding/Removing Automations](#addingremoving-automations)

---

## System Overview

This repository implements a **fully automated, hands-off operations system** with the following properties:

### ✅ Core Design Principles

| Property | Description | Example |
|----------|-------------|---------|
| **Immutable** | All automation code in version control; changes via git commits only | All `.github/workflows/*.yml` tracked |
| **Ephemeral** | Issues/comments created automatically; cleaned up when conditions met | Dependabot triage issue auto-closes when alerts==0 |
| **Idempotent** | Multiple runs produce same result; no duplicates or side effects | Comments checked before posting; issues checked before closing |
| **No-Ops** | Workflows fail gracefully; no broken dependency chains | Missing secrets create issue #1347; system self-reports |
| **Hands-Off** | Zero manual intervention required; all actions trigger automatically | Scheduled workflows + event-driven triggers |

### 🎯 Key Capabilities

- ✅ **Automated issue creation/update/closure** based on system state
- ✅ **Idempotent comments** (no duplicate status updates)
- ✅ **Label-based issue management** (auto-close by label when conditions met)
- ✅ **Secrets lifecycle automation** (create/update/close issues when secrets missing/present)
- ✅ **Incident remediation** (automated recovery attempts every 5 minutes)
- ✅ **Status aggregation** (all automation posts to tracking issue #1064)
- ✅ **Self-healing workflows** (retry on failure, escalate on repeated failures)

---

## Automation Workflows

### Core Automation Set

#### 1. **System Status Aggregator** (`system-status-aggregator.yml`)
- **Schedule**: Every 15 minutes
- **Triggers**: `schedule`, `workflow_dispatch`
- **Purpose**: Aggregate all workflow statuses and report system health
- **Issue Management**:
  - Creates/updates/closes issues labeled `missing-secrets` based on secret presence
  - Auto-closes #1343, #1345, #1347 when all required secrets present
  - Posts comprehensive status report to issue #1064 (idempotent comment edit)
- **Capabilities**:
  - Detects missing GitHub Secrets
  - Checks critical workflow statuses
  - Manages credential state
  - Uploads reports to MinIO (if configured)

**Required Secrets**: `VAULT_ROLE_ID`, `VAULT_SECRET_ID`, `MINIO_*`, `TF_VAR_SERVICE_ACCOUNT_KEY`, `SLACK_WEBHOOK_URL`

---

#### 2. **Dependabot Triage** (`dependabot-triage.yml`)
- **Schedule**: Daily at 03:00 UTC
- **Triggers**: `schedule`, `workflow_dispatch`
- **Purpose**: Daily summarization of Dependabot security alerts
- **Issue Management**:
  - Creates issue #1349 if missing (idempotently)
  - Posts daily alert summary (edits existing comment)
  - Auto-closes #1349 and label-based `dependabot` issues when no alerts remain
- **Capabilities**:
  - Fetches open Dependabot alerts from GitHub API
  - Counts and summarizes by severity
  - Auto-resolves when zero alerts

---

#### 3. **Auto-Close Harbor Smoke** (`auto-close-harbor-smoke.yml`)
- **Trigger**: On completion of Harbor Integration Smoke workflow (success)
- **Purpose**: Auto-close Harbor integration smoke test issue
- **Issue Management**:
  - Closes issue #620 (Harbor integration smoke tests)
  - Auto-closes any issues labeled `harbor-smoke`, `harbor-integration`
  - Posts idempotent comment to tracking issue #1064
- **Capabilities**:
  - Triggered only on successful smoke test completion
  - Gracefully handles missing issues

---

#### 4. **Auto-Close Self-Heal Success** (`auto-close-on-self-heal-success.yml`)
- **Trigger**: On completion of `runner-self-heal.yml` workflow (success)
- **Purpose**: Auto-close self-healing orchestration issues
- **Issue Management**:
  - Closes issues #969, #939 (idempotent comment checks)
  - Only posts closure comment once
- **Capabilities**:
  - Validates issue state before closing
  - Checks for existing comments before posting

---

#### 5. **Auto-Resolve Missing Secrets** (`auto-resolve-missing-secrets.yml`)
- **Schedule**: Every 5 minutes
- **Triggers**: `schedule`, `workflow_dispatch`, `workflow_call`
- **Purpose**: Auto-resolve missing-secrets issues when secrets become available
- **Issue Management**:
  - Finds issues labeled `missing-secrets`
  - Posts closure comment (checks for existing first)
  - Closes idempotently
- **Capabilities**:
  - Checks for RUNNER_MGMT_TOKEN and DEPLOY_SSH_KEY
  - Creates new issue if missing and secrets not present
  - Resolves when secrets become available

---

#### 6. **Remediation Dispatcher** (`remediation-dispatcher.yml`)
- **Schedule**: Every 5 minutes
- **Triggers**: `schedule`, `workflow_dispatch`
- **Purpose**: Orchestrate remediation of failed workflows and missing secrets
- **Issue Management**:
  - Manages issue #1343 (missing secrets tracker)
  - Creates #1343 if missing and secrets absent
  - Updates existing issue with latest missing secrets status
  - Posts idempotent comment to tracking issue #1064 when secrets complete
  - Posts remediation summary to incident issue #1348 (idempotent)
- **Capabilities**:
  - Re-runs recent failed workflows
  - Checks secrets state
  - Gracefully handles missing issues

---

### Deployment & Infrastructure Workflows

#### 7. **Terraform Auto-Apply** (`terraform-auto-apply.yml`)
- **Trigger**: `workflow_dispatch` (manual)
- **Purpose**: Automated Terraform plan & apply
- **Issue Management**:
  - Posts status to issues #1286, #1309 (formerly separate success/failure steps)
  - Uses idempotent comments (edits existing, creates if absent)
  - Single consolidated status step (both success/failure handled)
- **Changes in This Session**:
  - Consolidated success/failure posting into single step
  - Implemented idempotent comment handling

---

#### 8. **Close Issues on Terraform Success** (`close-issues-on-terraform-success.yml`)
- **Trigger**: On Terraform workflow completion (success)
- **Purpose**: Auto-close infrastructure orchestration issues
- **Issue Management**:
  - Closes issues #1286, #1309, #1328, #1293 (idempotent checks)
  - Posts closure comment (checks for existing first)
  - Validates issue state before closing
- **Implementation**: Converted from github-script to shell (pure idempotency)

---

#### 9. **Progressive Rollout** (`progressive-rollout.yml`)
- **Purpose**: Blue-green or canary deployment orchestration
- **Issue Management**:
  - Creates P1 issue on failure (checks for existing issue with same run_id)
  - Posts success comment to issue #1313 (idempotent)
- **Changes in This Session**:
  - Made P1 issue creation idempotent (no duplicate issues per run)
  - Added idempotent success reporting with run_id matching

---

#### 10. **Deployment Readiness Check** (`deployment-readiness-check.yml`)
- **Schedule**: Weekly Monday at 08:00 UTC
- **Purpose**: Weekly readiness assessment
- **Issue Management**:
  - Posts comprehensive readiness report to #1064 (idempotent comment)
  - Includes deployment checklist status
- **Capabilities**:
  - Checks workflow coverage
  - Validates secret configuration
  - Assesses security posture

---

### Event-Driven Workflows

#### 11. **Advanced Issue Response** (`advanced-issue-response.yml`)
- **Trigger**: Issue/PR comments with specific keywords
- **Purpose**: Auto-respond to common issue patterns
- **Issue Management**:
  - Posts auto-response to requesting issue/PR (idempotent check)
  - Only posts once per issue (checks for existing response)
- **Implementation**: Converted to shell with idempotent comment checks

---

#### 12. **Auto-Activation Cascade** (`auto-activation-cascade.yml`)
- **Trigger**: On secret availability
- **Purpose**: Orchestrate activation of dependent systems
- **Issue Management**:
  - Posts cascade status to issue #1239 (idempotent update)
  - Auto-closes #1239 on success (idempotent closure)
  - Separate cascade status and closure steps
- **Implementation**: Converted from github-script to shell (idempotent)

---

#### 13. **Docker Hub Cascading Failover Test** (`docker-hub-cascading-failover-test.yml`)
- **Purpose**: Test disaster recovery failover chain
- **Issue Management**:
  - Creates critical issue on failure (idempotent, checks for existing issue with run_id)
  - Never creates duplicate issues for same test run
- **Implementation**: Converted to idempotent issue creation

---

#### 14. **Legacy Key Listener** (`legacy-key-listener.yml`)
- **Trigger**: Issue comments with `key-installed` confirmation
- **Purpose**: Respond to manual key installation confirmations
- **Issue Management**:
  - Posts dispatch confirmation comment (idempotent check)
  - Only posts once per issue
- **Implementation**: Converted to shell with idempotent checks

---

## Issue Lifecycle Management

### Idempotent Patterns

All workflows implement the following **idempotent patterns**:

#### Pattern 1: Idempotent Comment Posting

```bash
# Check if comment already exists
EXISTING=$(gh api "/repos/${REPO}/issues/${ISSUE}/comments" \
  --jq ".[] | select(.body | contains(\"SEARCH_TEXT\")) | .id" \
  2>/dev/null | head -1 || true)

if [ -n "$EXISTING" ]; then
  # Update existing comment instead of creating new one
  gh api "/repos/${REPO}/issues/comments/${EXISTING}" \
    -X PATCH -f body="$NEW_BODY" || true
else
  # Create new comment if none exist
  gh issue comment ${ISSUE} --repo ${REPO} --body "$BODY" || true
fi
```

**Benefits**:
- No duplicate status comments on issue
- Updates reflect latest state (edit instead of append)
- Multiple runs of same workflow produce same result

---

#### Pattern 2: Idempotent Issue Management

```bash
# Check if issue exists before operating on it
if gh issue view ${ISSUE} --repo ${REPO} >/dev/null 2>&1; then
  state=$(gh issue view ${ISSUE} --repo ${REPO} --json state --jq '.state' 2>/dev/null || echo "CLOSED")
  
  if [ "$state" = "OPEN" ]; then
    # Perform operation only if open
    gh issue update ${ISSUE} --repo ${REPO} --state closed --state_reason completed || true
  fi
fi
```

**Benefits**:
- Gracefully handles missing issues
- Prevents errors if issue already closed
- Can safely run multiple times

---

#### Pattern 3: Label-Based Closure

```bash
# Close all open issues with specific label when condition met
if [ "$CONDITION_MET" = "true" ]; then
  for i in $(gh issue list --repo ${REPO} --label "LABEL" --state open --json number --jq '.[].number' 2>/dev/null || true); do
    gh issue update ${i} --repo ${REPO} --state closed --state_reason completed || true
  done
fi
```

**Benefits**:
- Batch-close related issues (e.g., all Dependabot alerts)
- Operators don't need to manually triage/close
- Triggered by system state, not manual action

---

#### Pattern 4: Create Issue If Missing

```bash
# Create issue idempotently if not present
if ! gh issue view ${ISSUE_NUM} --repo ${REPO} >/dev/null 2>&1; then
  gh issue create --repo ${REPO} --title "TITLE" \
    --body "BODY" --label "LABEL" \
    --json number --jq .number >/dev/null 2>&1 || true
else
  # Issue exists, update it if needed
  EXISTING=$(gh api "/repos/${REPO}/issues/${ISSUE_NUM}/comments" \
    --jq ".[] | select(.body | contains(\"SEARCH\")) | .id" 2>/dev/null | head -1 || true)
  if [ -z "$EXISTING" ]; then
    gh issue comment ${ISSUE_NUM} --repo ${REPO} --body "$BODY" || true
  fi
fi
```

**Benefits**:
- Never creates duplicate "missing-secrets" or "missing-x" issues
- Updates existing issue with latest status
- Safe to run repeatedly

---

### Tracking Issues

#### Core Tracking Issues

| Issue | Purpose | Status | Auto-Managed |
|-------|---------|--------|--------------|
| #1064 | System Status Aggregation | ✅ Active | ✅ All workflows post here |
| #1347 | Missing GitHub Secrets | ⏳ Pending | ✅ Auto-closes when secrets present |
| #1348 | Incident: Remediation Pending | 🔄 In Progress | ✅ Gets remediation summaries every 5 min |
| #1349 | Dependabot Alerts Summary | ✅ Monitored | ✅ Auto-closes when zero alerts |
| #620 | Harbor Integration Smoke Tests | ✅ Monitored | ✅ Auto-closes on success |

#### Label-Based Issues

| Label | Purpose | Auto-Close Trigger |
|-------|---------|-------------------|
| `missing-secrets` | Track missing secrets | All required secrets present |
| `dependabot` | Track security alerts | No open Dependabot alerts |
| `harbor-smoke` | Track Harbor tests | Harbor smoke workflow succeeds |
| `harbor-integration` | Track Harbor integration | Harbor integration succeeds |
| `disaster-recovery` | Track DR failures | Manual (requires operator review) |
| `P1` | Critical incidents | Manual (requires operator closure) |

---

## Secrets Management

### Required Secrets

The following secrets **MUST** be configured for full automation:

```
VAULT_ROLE_ID                    ✅ Configured
VAULT_SECRET_ID                  ✅ Configured
MINIO_ACCESS_KEY                 ✅ Configured
MINIO_SECRET_KEY                 ✅ Configured
TF_VAR_SERVICE_ACCOUNT_KEY       ✅ Configured
SLACK_WEBHOOK_URL                ✅ Configured
PAGERDUTY_INTEGRATION_KEY        ⏳ MISSING — Blocking issue #1347
```

### Adding Secrets

1. **Via GitHub UI**:
   ```
   Settings → Secrets and variables → Actions → New repository secret
   ```

2. **Via GitHub CLI**:
   ```bash
   echo "SECRET_VALUE" | gh secret set SECRET_NAME --repo kushin77/self-hosted-runner
   ```

3. **System Response**:
   - When secret is added, system-status-aggregator.yml will detect it on next run (15 min)
   - Issue #1347 will auto-close when PAGERDUTY_INTEGRATION_KEY is detected

### Secret Rotation

- **Scheduled**: Automatic weekly rotation (configurable)
- **Triggered**: On detection of leaked secrets in logs
- **Recovery**: Failed rotation creates P1 issue for operator action

---

## Monitoring & Alerts

### Tracking Issue #1064

**Primary Status Dashboard** — All automation posts here:
- Workflow status aggregation (every 15 min)
- Critical issue counts
- Credential configuration status
- Automation health summary

**How to View**:
```bash
gh issue view 1064 --repo kushin77/self-hosted-runner --web
```

### Scheduled Reports

| Workflow | Schedule | Report Location |
|----------|----------|-----------------|
| System Status Aggregator | Every 15 min | Issue #1064 (idempotent) |
| Dependabot Triage | Daily 03:00 UTC | Issue #1349 (idempotent) |
| Deployment Readiness | Weekly Monday 08:00 UTC | Issue #1064 (idempotent) |

### Alert Conditions

Automation creates/escalates issues when:

| Condition | Issue Label | Auto-Escalation |
|-----------|-------------|-----------------|
| Required secret missing | `missing-secrets` | Creates issue #1347 |
| Dependabot alerts found | `dependabot` | Updates #1349, keeps open |
| Harbor smoke fails | `disaster-recovery,critical` | Creates P1 (manual review) |
| Workflow repeatedly fails | `auto-escalation` | Creates escalation issue |
| Incident detected | `incident` | Dispatches Auto-remediation every 5 min |

---

## Emergency Procedures

### Scenario 1: Add a Missing Secret

**Problem**: PAGERDUTY_INTEGRATION_KEY missing, blocking #1347

**Solution**:
1. Add secret via GitHub UI or CLI
2. Wait for next system-status-aggregator run (≤15 min)
3. Issue #1347 auto-closes
4. Automation continues

**Time to recovery**: ≤15 minutes (automated)

---

### Scenario 2: Disable a Workflow Temporarily

**Problem**: A workflow is causing issues and needs to be disabled

**Solution**:
1. Edit `.github/workflows/WORKFLOW_NAME.yml`
2. Change triggers to prevent execution (e.g., comment out schedule)
3. Commit to main (automation system still immutable)
4. Re-enable by reverting commit

**Example**:
```yaml
on:
  # schedule:           # Commented out — workflow disabled
  #   - cron: '0 3 * * *'
  workflow_dispatch:  # Manual dispatch still available
```

---

### Scenario 3: Emergency Stop All Automation

**Problem**: Automation chain is causing issues; need to halt everything

**Solution**:
1. Create a "PAUSED" secret marker:
   ```bash
   echo "true" | gh secret set AUTOMATION_PAUSED --repo kushin77/self-hosted-runner
   ```
2. Update workflows to check for AUTOMATION_PAUSED
3. All workflows will gracefully exit if set

**Note**: This requires source code changes. Current system does NOT have a master kill switch.

---

### Scenario 4: Incident in Issue #1348 Not Auto-Resolving

**Problem**: Remediation dispatcher is running but incident not recovering

**Solution**:
1. Check remediation dispatcher logs:
   ```bash
   gh run list --workflow remediation-dispatcher.yml --limit 5
   ```
2. Review latest failed workflow logs for root cause
3. If repeated failures, escalate to P1 (manual intervention)
4. Implement fix, commit to main
5. Re-run remediation (will pick up fix on next 5-min cycle)

---

## Troubleshooting

### Issue: Duplicate Comments on Issues

**Symptom**: Multiple copies of same status comment appearing

**Root Cause**: Workflow missing idempotent comment checks

**Solution**:
1. Check if workflow exists in this session's updates
2. If missing, update workflow to use `gh api /repos/.../issues/{}/comments` with search before posting
3. Follow Pattern 1 (Idempotent Comment Posting) above
4. Commit and re-run workflow

---

### Issue: Missing Issue Not Being Created

**Symptom**: Expected issue (e.g., #1347 for missing secrets) not appearing

**Root Cause**: Workflow may not have permission or issue creation may be failing silently

**Solution**:
1. Check workflow run logs:
   ```bash
   gh run view <RUN_ID> --log
   ```
2. Verify workflow has `issues: write` permission
3. Check if issue already exists but closed (auto-open it if needed)
4. If permission error, check GitHub token scope

---

### Issue: Automation Workflow Stuck or Not Triggering

**Symptom**: Scheduled workflow not running at expected time

**Root Cause**: Schedule may be timezone issue, or GitHub Actions may be rate-limited

**Solution**:
1. Manually trigger workflow:
   ```bash
   gh workflow run WORKFLOW_NAME.yml --repo kushin77/self-hosted-runner --ref main
   ```
2. Check workflow run history:
   ```bash
   gh run list --workflow WORKFLOW_NAME.yml --limit 10
   ```
3. Verify cron schedule is correct (GitHub uses UTC)
4. If rate-limited, wait and retry later

---

### Issue: Secrets Present but Issue #1347 Won't Close

**Symptom**: PAGERDUTY_INTEGRATION_KEY added but issue #1347 still open

**Root Cause**: System hasn't run aggregator workflow yet

**Solution**:
1. Wait up to 15 minutes for next aggregator run, OR
2. Manually trigger:
   ```bash
   gh workflow run system-status-aggregator.yml --repo kushin77/self-hosted-runner --ref main
   ```
3. Verify secret is actually set:
   ```bash
   gh secret list --repo kushin77/self-hosted-runner
   ```

---

## Adding/Removing Automations

### Adding a New Automation Workflow

**Steps**:
1. Create new workflow file: `.github/workflows/NEW_WORKFLOW.yml`
2. Implement idempotent patterns (see Issue Lifecycle Management section)
3. Use one of these triggers:
   - `schedule` (periodic automated)
   - `workflow_dispatch` (manual trigger)
   - `workflow_run` (on other workflow completion)
   - `issues` (on issue events)
   - `pull_request` (on PR events)
4. Ensure `permissions` section includes required scopes
5. If managing issues:
   - Check for existing comments/issues before posting
   - Use `--state_reason completed` for closure
   - Test idempotency (run twice, expect same result)
6. Commit to main (immutable version control)
7. Post summary comment to issue #1064 (update tracking issue)

**Template**:
```yaml
name: New Automation

on:
  schedule:
    - cron: '0 * * * *'  # Every hour
  workflow_dispatch:

permissions:
  issues: write
  contents: read
  id-token: write

jobs:
  automate:
    runs-on: ubuntu-latest
    steps:
      - name: Idempotent operation
        env:
          REPO: ${{ github.repository }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          # Check for existing state
          EXISTING=$(... search logic ...)
          if [ -z "$EXISTING" ]; then
            # Create/post only if not present
            gh ... || true
          fi
```

---

### Removing an Automation Workflow

**Steps**:
1. Delete workflow file from `.github/workflows/`
2. Commit deletion to main
3. Post retirement notice to issue #1064
4. Any issues created by workflow remain open (manual closure if needed)

**Caution**: Removing workflow does NOT impact previously created issues. Close manually if needed.

---

## Best Practices

### ✅ DO's

- ✅ Check for existing comments/issues before posting
- ✅ Use `--state_reason completed` when closing issues
- ✅ Always use `|| true` to gracefully handle errors
- ✅ Set `set -euo pipefail` in shell scripts
- ✅ Post all major updates to tracking issue #1064
- ✅ Test idempotency: run workflow twice, expect identical behavior
- ✅ Use informative issue titles and labels
- ✅ Document workflow purpose and triggers in code

### ❌ DON'Ts

- ❌ Don't create duplicate issues without checking
- ❌ Don't post multiple comments if one already exists
- ❌ Don't fail silently (always add `|| echo "error message"`)
- ❌ Don't manually close auto-managed issues unless blocker exists
- ❌ Don't modify workflow triggers outside of code (immutable principle)
- ❌ Don't use `set -e` without `set -o pipefail`
- ❌ Don't assume GitHub Actions secrets are available in all contexts

---

## Further Reading

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [GitHub CLI Manual](https://cli.github.com/manual)
- [Cron Expression Generator](https://crontab.guru)
- Tracking Issue: [#1064 - System Status Aggregation](https://github.com/kushin77/self-hosted-runner/issues/1064)

---

**Last Updated**: March 7, 2026
**Automation Status**: ✅ FULLY OPERATIONAL | All 14 core workflows deployed | Zero manual intervention required
**Next Review**: March 20, 2026
