# Automated 5-System Operations

**Status**: ✅ AUTOMATED & HANDS-OFF  
**Last Updated**: March 8, 2026

---

## Automation Overview

The 5-System Organizational Framework now includes **fully automated validation workflows** that ensure all indices stay synchronized with reality.

### Scheduled Audits

| Workflow | Schedule | Purpose | Status |
|----------|----------|---------|--------|
| **audit-validation-pr.yml** | On every PR | Validate scripts, indices stay in sync | ✅ Active |
| **audit-weekly.yml** | Every Monday 6 AM UTC | Full system health check | ✅ Active |

---

## What Runs Automatically

### On Every Pull Request

When you create a PR that touches workflows, scripts, or indices:

```yaml
✅ Validate Secrets Index     # Run audit-secrets.sh --validate
✅ Validate Workflows Index   # Run audit-workflows.sh --validate  
✅ Validate Scripts Registry  # Run audit-scripts.sh --validate
✅ Check All Script Syntax    # Bash -n on all scripts
✅ Cross-Index Consistency    # Count current vs documented items
```

**Result**: You get immediate feedback if indices are out of sync.

### Weekly (Every Monday 6 AM UTC)

Full automated health check runs:

```yaml
✅ Full Secrets Audit          # Generates secrets-audit-report + JSON export
✅ Full Workflows Audit        # Generates workflows-audit-report + JSON export
✅ Full Scripts Audit          # Generates scripts-audit-report + JSON export
✅ System Health Check         # Creates issue if inconsistencies detected
```

**Result**: Artifacts saved for 30 days, automatic issue creation if problems found.

---

## Audit Artifacts

Each weekly run produces downloadable reports:

- **secrets-audit-report** — Full secrets inventory
- **secrets-export-json** — Machine-readable secrets
- **workflows-audit-report** — Full workflows inventory
- **workflows-export-json** — Machine-readable workflows
- **scripts-audit-report** — Full scripts inventory
- **scripts-export-json** — Machine-readable scripts

**How to access**:
1. Go to: Actions → audit-weekly workflow
2. Click latest run
3. Scroll to "Artifacts" section
4. Download any report

---

## Hands-Off Features

### ✨ Idempotent
- Audit scripts can run multiple times, always produce same result
- No state changes, side effects, or manual cleanup needed

### ✨ Ephemeral
- All workflows use clean, fresh runners
- No persistent state or artifact pollution
- Old reports automatically deleted after 30 days

### ✨ Fully Automated
- Triggers via GitHub Actions cron and PR events
- Automatic issue creation if problems detected
- No manual intervention required

### ✨ No Ops Required
- Audit tools are self-contained bash scripts
- No external services, dependencies, or API calls
- Runs on any runner: GitHub-hosted or self-hosted

---

## Continuous Integration

### Before PR Merge

All PRs touching key files trigger 5 validation jobs:

```bash
# Job 1: Secrets validation
bash scripts/audit-secrets.sh --validate

# Job 2: Workflows validation
bash scripts/audit-workflows.sh --validate

# Job 3: Scripts validation
bash scripts/audit-scripts.sh --validate

# Job 4: Script syntax check
find scripts -name "*.sh" -type f -executable | while read s; do
  bash -n "$s" || exit 1
done

# Job 5: Consistency check
# Counts current items vs documented in indices
```

**Failure = PR cannot merge** (can be overridden by admins if needed)

### Weekly Full Check

Every Monday 6 AM UTC:

```bash
# 1. Generate full audit reports
bash scripts/audit-secrets.sh --full > report.txt
bash scripts/audit-workflows.sh --full > report.txt
bash scripts/audit-scripts.sh --full > report.txt

# 2. Export JSON for tooling
bash scripts/audit-secrets.sh --json > secrets.json
bash scripts/audit-workflows.sh --json > workflows.json
bash scripts/audit-scripts.sh --json > scripts.json

# 3. Create GitHub issue if inconsistencies found
# (automatic via workflow_dispatch)
```

---

## What Gets Validated

### Secrets
- ✅ All secrets follow naming convention
- ✅ No duplicate secret definitions
- ✅ All GitHub-used secrets documented
- ✅ Required secrets are configured

### Workflows
- ✅ All .yml files have valid YAML syntax
- ✅ Each workflow has a `name:` field
- ✅ Each workflow has a trigger (`on:`)
- ✅ Each workflow has `jobs:` section
- ✅ All workflows documented in index

### Scripts
- ✅ All scripts have proper shebang
- ✅ Script syntax is valid bash/sh
- ✅ Critical scripts identified
- ✅ All scripts have execution permissions
- ✅ All scripts documented in registry

---

## Integration with Development Workflow

### When You're Adding Something

**Adding a Secret?**
```bash
# 1. Add in GitHub Settings → Secrets
# 2. Update SECRETS_INDEX.md
# 3. Push PR
# 4. Audit workflow runs automatically ✅
# 5. If validation fails: fix & push again
```

**Adding a Workflow?**
```bash
# 1. Create .github/workflows/my-workflow.yml
# 2. Update WORKFLOWS_INDEX.md
# 3. Push PR
# 4. Audit workflow validates immediately ✅
# 5. All checks pass = ready to merge!
```

**Adding a Script?**
```bash
# 1. Create scripts/my-script.sh with shebang
# 2. chmod +x scripts/my-script.sh
# 3. Update SCRIPTS_REGISTRY.md
# 4. Push PR
# 5. Audit checks syntax & validates ✅
```

---

## Emergency: What If Audit Fails?

### PR Validation Fails

**Example**: Added workflow but forgot to update WORKFLOWS_INDEX.md

```
❌ validate-workflows step failed
   Error: Workflow count mismatch (198 found, 197 in index)
```

**Fix**:
1. Update [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)
2. Push new commit
3. Audit reruns automatically ✅

### Weekly Audit Creates Issue

**When**: Inconsistency detected during Monday's run

**Action**:
1. GitHub creates issue automatically
2. Issue includes link to failed workflow run
3. Review audit logs → identify mismatch
4. Update relevant index → close issue

---

## Audit Tool Usage (Manual)

You can also run audits manually anytime:

```bash
# Full secret inventory
bash scripts/audit-secrets.sh --full

# Find workflows matching pattern
bash scripts/audit-workflows.sh --search "terraform"

# Show only critical scripts
bash scripts/audit-scripts.sh --critical

# Validate everything
bash scripts/audit-secrets.sh --validate
bash scripts/audit-workflows.sh --validate
bash scripts/audit-scripts.sh --validate
```

---

## Configuration

### Edit Schedules

**File**: `.github/workflows/audit-weekly.yml`

```yaml
on:
  schedule:
    # Change this cron expression to adjust timing
    - cron: '0 6 * * 1'  # Monday 6 AM UTC
```

**Common Cron Patterns**:
- `0 6 * * 1` = Every Monday 6 AM UTC
- `0 9 * * *` = Every day 9 AM UTC
- `0 */6 * * *` = Every 6 hours

### Edit Retention

**File**: `.github/workflows/audit-weekly.yml`

```yaml
- uses: actions/upload-artifact@v3
  with:
    name: secrets-audit-report
    retention-days: 30  # Change to desired days (1-90)
```

---

## Monitoring & Alerts

### Check Recent Audit Runs

**In GitHub**:
1. Go to: Actions tab
2. Filter by: "audit-" workflows
3. Click any run to see full details

### Disable Audit Temporarily

```bash
# Disable PR validation workflow
gh workflow disable audit-validation-pr.yml

# Disable weekly audit
gh workflow disable audit-weekly.yml

# Re-enable later
gh workflow enable audit-validation-pr.yml
```

### View Audit Logs

```bash
# List all audit workflow runs
gh run list --workflow audit-weekly.yml --limit 10

# View specific run
gh run view RUN_ID --log
```

---

## Metrics & SLOs

### Uptime SLA

- **PR Validation**: Should complete in <2 minutes per run
- **Weekly Audit**: Should complete in <5 minutes per run

### Coverage

- **100%** of secrets audited
- **100%** of workflows audited
- **100%** of scripts audited
- **20+** error codes maintained

### False Positives

- Target: <1% false positive rate
- Action: Create issue, update audit logic, deploy fix

---

## Related Documentation

- [5-SYSTEMS-INTEGRATION.md](5-SYSTEMS-INTEGRATION.md) — Main integration guide
- [SECRETS_INDEX.md](SECRETS_INDEX.md) — Secrets system
- [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md) — Workflows system
- [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md) — Scripts system
- [ERROR_CODES_GUIDE.md](ERROR_CODES_GUIDE.md) — Error reference
- [CONFIGURATION_GUIDE.md](CONFIGURATION_GUIDE.md) — Configuration reference

---

## Troubleshooting

### "Audit validation failed on my PR"

**Action**: 
1. Check which job failed in PR checks
2. Review exact error message
3. Update corresponding index file
4. Push new commit (audit reruns automatically)

### "Weekly audit created an issue"

**Action**:
1. Click issue link to see audit run
2. Review artifact logs
3. Identify which system is out of sync
4. Update index or fix code
5. Close issue (or let Monday's run auto-validate)

### "Audit script isn't finding my new [secret/workflow/script]"

**Likely cause**: File doesn't match discovery pattern

**Check**:
- Secret: Is it in GitHub Settings → Secrets?
- Workflow: Is file in `.github/workflows/` with `.yml` extension?
- Script: Is file in `scripts/` with execution bit set?

```bash
# Verify
bash scripts/audit-secrets.sh --full | grep YOUR_ITEM
bash scripts/audit-workflows.sh --full | grep YOUR_FILE
bash scripts/audit-scripts.sh --full | grep YOUR_SCRIPT
```

---

## Future Enhancements

**Possible additions** (not yet implemented):
- [ ] Export audit data to CloudWatch/DataDog
- [ ] Create dashboard of audit trends
- [ ] Slack notifications on audit failures
- [ ] Auto-create PRs to fix index inconsistencies
- [ ] Integration with CODEOWNERS for audit reviews

**No plans for**:
- Additional audit tools (bash is sufficient)
- Web UI (CLI + artifacts sufficient)
- External dependencies (keep scripts self-contained)

---

*Last Updated: March 8, 2026*  
*Automation Status: ✅ PRODUCTION-READY*  
*Next Audit: Every Monday 6 AM UTC*
