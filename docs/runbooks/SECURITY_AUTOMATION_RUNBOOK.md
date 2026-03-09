# Security Automation Runbook
## Hands-Off, Idempotent, Immutable Security Remediation

**Date**: March 7, 2026  
**Status**: Production-Ready  
**Maintenance**: Fully Automated

---

## Executive Summary

This runbook documents the fully automated security remediation pipeline for continuous vulnerability detection, reporting, and hands-off remediation. The system operates 24/7 with no manual intervention required after initial setup.

**Key Principles**:
- ✅ **Immutable**: Once deployed, no manual changes to workflows
- ✅ **Ephemeral**: Runs are self-contained and idempotent
- ✅ **Idempotent**: Safe to re-run; produces same result
- ✅ **Hands-Off**: Zero manual intervention post-deployment

---

## Architecture Overview

```
Daily Security Audit (02:00 UTC)
    ↓ gitleaks + trivy scans
    ↓ artifacts: gitleaks-report.json, trivy-report.json
    ↓
Polling Service (every 30 min)
    ↓ detects completed audit run
    ↓
Auto-Remediation Workflow
    ├─ Parse findings (gitleaks/trivy)
    ├─ Run npm audit fix
    ├─ Create remediation Draft issues (auto-merge enabled)
    └─ Auto-close parent issue on merge
    ↓
Issue Tracking & Closure (hourly)
    └─ Tracks PR status, closes resolved issues
```

---

## Workflow Components

### 1. Security Audit Workflow (`.github/workflows/security-audit.yml`)
- **Trigger**: Daily @ 02:00 UTC (cron) or manual dispatch
- **Tasks**:
  - Run Gitleaks v7.4.0: detect secrets in repository history
  - Run Trivy: filesystem scan for High/Critical CVEs
  - Generate JSON reports
  - Upload artifacts to GitHub Actions
  - Create GitHub issues with findings (labeled `security,gitleaks` or `security,trivy`)
- **SLA**: Should complete within 5 minutes
- **Artifacts**: `gitleaks-report.json`, `trivy-report.json`

### 2. Security Audit Polling Workflow (`.github/workflows/security-audit-polling.yml`)
- **Trigger**: Every 30 minutes (scheduled) or manual dispatch
- **Tasks**:
  - Query for completed `security-audit.yml` runs
  - Avoid duplicate triggering (check if remediation already run for this audit)
  - Automatically dispatch `security-findings-remediation.yml` if new audit found
  - Poll remediation PR status
  - Report summary to automated tracking issue (label: `security-polling-summary`)
- **Idempotence**: Checks recent remediation runs to prevent duplicate flow

### 3. Auto-Remediation Workflow (`.github/workflows/security-findings-remediation.yml`)
- **Trigger**: 
  - On GitHub issue opened (if title contains `[SECURITY]` + `Trivy` or `Gitleaks`)
  - Via `security-audit-polling.yml` dispatch
  - Manual workflow_dispatch with optional issue number
- **Tasks**:
  - Download latest audit artifacts (trivy/gitleaks reports)
  - Parse findings (High/Critical vulnerabilities)
  - Run `npm audit fix` for fixable npm packages
  - Create remediation Draft issues for each module with changes
  - Label Draft issues: `security,remediation-auto`
  - Enable auto-merge (squash) on Draft issues
  - Post status comment to parent issue
- **Output**: Creates Draft issues or opens manual remediation issues
- **Auto-Merge**: Enabled; merges when all CI checks pass

### 4. Security Tracker Workflow (`.github/workflows/security-tracker.yml`)
- **Trigger**: Hourly schedule or on PR events
- **Tasks**:
  - Monitor remediation Draft issues
  - Track PR → merge → close parent issue flow
  - Auto-close security issues when all related Draft issues merged
  - Update issue with remediation PR links
- **Result**: Full closure of security issues once remediation complete

---

## Operational Flow

### Hour 0: Audit Run Triggered
```
02:00 UTC: security-audit.yml scheduled run starts
  └─> Gitleaks scans repository
  └─> Trivy scans filesystem
  └─> Creates issue if findings detected
  └─> Uploads artifacts
```

### Hour 0+: Polling Detects Audit Run
```
02:30-03:00 UTC: security-audit-polling.yml runs
  └─> Detects completed audit run
  └─> Checks if remediation already triggered (prevent duplicates)
  └─> Dispatches security-findings-remediation.yml
  └─> Reports status to tracking issue
```

### Hour 1: Remediation Workflow Runs
```
02:30-03:30 UTC: security-findings-remediation.yml runs
  └─> Downloads trivy-report.json artifact
  └─> Parses vulnerabilities
  └─> Runs npm audit fix (if npm packages affected)
  └─> Creates remediation Draft issues for each module with changes
  └─> Enables auto-merge on Draft issues
  └─> Posts status to parent issue
```

### Hour 2-24: CI + Merge + Closure
```
03:30-04:30 UTC: GitHub CI checks run on remediation Draft issues
  └─> Once all checks pass, auto-merge enabled
  └─> Draft issues land on main
  └─> security-tracker.yml detects merged Draft issues
  └─> Auto-closes parent issue
  └─> Issue marked as resolved
```

---

## Sequence & Idempotence Guards

### Preventing Duplicate Remediation Runs
The polling workflow checks:
```bash
# Recent remediation runs (within last 5 minutes)
gh run list --workflow security-findings-remediation.yml \
  --status completed --limit 10 \
  --json createdAt | jq ".[] | select(.createdAt > last_5_min)"
```

If recent runs exist, polling skips dispatch. This ensures:
- ✅ No duplicate workflow triggers
- ✅ One audit → one remediation flow
- ✅ Idempotent operation

### Non-Breaking Fix Guards
The remediation workflow attempts `npm audit fix` (non-breaking):
```bash
npm audit fix --production --audit-level=high
```

If no changes result (breaking fixes required):
- Creates manual remediation issue (label: `security,remediation-manual`)
- Requires human review + approval
- Prevents automatic deployment of risky changes

---

## Secrets & Prerequisites

### Required Repository Secrets
The following secrets must be provisioned by admins (see PR #1181 for SECRETS.md):

1. **RUNNER_MGMT_TOKEN** (optional): PAT for runner lifecycle mgmt
2. **DEPLOY_SSH_KEY** (optional): SSH key for deployment runner configs
3. **GCP_SERVICE_ACCOUNT_KEY** (for DR): GCP service account JSON
4. **GCP_PROJECT_ID** (for DR): GCP project ID

### How to Provision
See [SECRETS.md](../SECRETS.md) for step-by-step instructions or issue #969.

---

## Monitoring & Alerts

### Key Issues to Watch
- **#1184**: Aggregated automation status + blocker tracking
- **#1186**: Synthetic test issues for immediate remediation validation
- **security-polling-summary**: Automated hourly polling status
- **security,remediation-auto**: Active remediation Draft issues (auto-labeled)

### How to Check Status
```bash
# List all open security issues
gh issue list --repo kushin77/self-hosted-runner --label security --state open

# View latest audit artifacts
gh run list --repo kushin77/self-hosted-runner --workflow security-audit.yml --limit 1

# List active remediation Draft issues
gh pr list --repo kushin77/self-hosted-runner --label remediation-auto --state open

# Check polling workflow status
gh run list --repo kushin77/self-hosted-runner --workflow security-audit-polling.yml --limit 5
```

---

## Troubleshooting

### Problem: No Remediation Draft issues Created After Audit
**Diagnosis**:
1. Check if audit artifacts were uploaded:
   ```bash
   gh run view <RUN_ID> --log | grep -i "trivy-report"
   ```
2. Check if polling detected the audit run:
   ```bash
   gh run list --workflow security-audit-polling.yml --limit 1
   ```
3. Check if remediation workflow was triggered:
   ```bash
   gh run list --workflow security-findings-remediation.yml --limit 5
   ```

**Solution**:
- Manual dispatch remediation: `gh workflow run security-findings-remediation.yml --ref main`
- Verify audit artifacts exist before dispatch

### Problem: Workflow Dispatch Returns HTTP 422
**Cause**: GitHub cache delay or workflow not registered  
**Solution**:
1. Push a no-op commit to force re-registration:
   ```bash
   echo "# re-register" >> .github/workflows/security-audit.yml
   git add .github/workflows/security-audit.yml && git commit -m "chore: re-register workflow"
   ```
2. Wait 5-10 minutes for GitHub to update cache
3. Retry dispatch

### Problem: Missing Secrets, DR Tests Fail
**Diagnosis**: Look for error messages in workflow logs:
```
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
```
**Solution**: Provision secrets per PR #1181 and issue #969

### Problem: Manual Remediation Issues Not Creating
**Possible Reasons**:
- npm audit fix requires breaking changes
- No package.json files affected
- Issue creation failed silently

**Diagnosis**:
```bash
# Check if manual remediation issues exist
gh issue list --repo kushin77/self-hosted-runner \
  --label remediation-manual --state all
```

---

## Integration Points

### CI/CD Pipeline
- Remediation Draft issues trigger full CI suite (tests, lints, builds)
- Auto-merge only enabled if all checks pass
- Maintains code quality standards

### Issue Tracking System
- Parent security issues created by audit workflow
- Remediation Draft issues linked to parent issue via comments
- Auto-closure when all Draft issues merged

### GitHub Actions Artifacts
- Uploaded by: `security-audit.yml`
- Downloaded by: `security-findings-remediation.yml`
- Retention: 90 days (GitHub default)
- Format: JSON (trivy-report.json, gitleaks-report.json)

---

## Performance & Costs

| Component | Frequency | Duration | Cost |
|-----------|-----------|----------|------|
| Security Audit | Daily @ 02:00 UTC | ~5 min | ~$0.0083 (10 min runs) |
| Polling | Every 30 min | ~30 sec | ~$0.008 per poll |
| Remediation | Per audit | ~2 min | ~$0.0025 per run |
| Tracker | Hourly | ~30 sec | ~$0.008 per hour |
| **Total/Month** | — | — | **~$5-10** |

*(Estimates based on GitHub Actions pricing: $0.0025 per min on ubuntu-latest)*

---

## Future Enhancements

- [ ] Integration with security scanning service (Snyk, Checkmarx)
- [ ] Slack/email notifications for critical findings
- [ ] Custom remediation rules per team
- [ ] Metrics dashboard (vulnerabilities over time)
- [ ] Manual remediation PR templates
- [ ] Integration with internal bug bounty system

---

## References & Links

- **Workflows**: [`.github/workflows/`](.github/workflows/)
  - `security-audit.yml` — Main audit scan
  - `security-audit-polling.yml` — Hands-off polling
  - `security-findings-remediation.yml` — Auto-remediation
  - `security-tracker.yml` — PR tracking & closure
- **Issues**:
  - #969: Secrets provisioning request
  - #1178: DR investigation
  - #1182: Synthetic test issue
  - #1184: Aggregated automation status
  - #1186: Auto-test trigger (synthetic)
  - #1201: Polling workflow PR
- **Documentation**:
  - PR #1181: SECRETS.md (provisioning guide)
  - PR #1173: Automation hardening summary

---

## Support & Escalation

### For Security Issues
- **Urgent**: Create issue with label `security,urgent`
- **Investigation**: See #1178 for consolidated DR/blocker issues
- **Manual Remediation**: See remediation-manual labeled issues

### For Automation Issues
- **Workflow Failures**: Check issue #1184 (aggregated status)
- **Polling Problems**: Check security-polling-summary issues
- **PR Auto-Merge**: Ensure CI passes; check branch protection rules

### Administrative Actions
- **Provision Secrets**: See SECRETS.md (issue #969)
- **Escalate Blocker**: Comment on #1184
- **Force Re-Run**: Manual dispatch via `gh workflow run`

---

## Sign-Off

**Deployment Date**: March 7, 2026  
**Deployed By**: GitHub Copilot Automation  
**Status**: ✅ Production Ready, Hands-Off Mode Active  
**Maintenance Mode**: Zero manual intervention required (post-secrets provisioning)

---

*Last Updated: March 7, 2026*
