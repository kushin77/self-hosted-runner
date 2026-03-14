# Production Hardening Operations Runbook

**Date Created:** 2026-03-14  
**Version:** 1.0  
**Status:** ✅ Production Ready  

---

## Quick Start

### Run All Hardening Phases (Safe DRY-RUN Mode)

```bash
cd /home/akushnir/self-hosted-runner
bash scripts/orchestration/hardening-master.sh --phase all
```

This executes all 5 hardening phases without making any mutations. Perfect for validation.

### Execute Hardening with Mutations (Requires Explicit Flag)

```bash
bash scripts/orchestration/hardening-master.sh --phase all --execute --strict
```

- `--execute`: Perform actual mutations and aggregations
- `--strict`: Fail fast on first error (vs. continue on non-blocking errors)

---

## The 5 Hardening Phases

### Phase 1: Portal/Backend Zero-Drift Validation

**Purpose:** Validate portal and backend services are synchronized

**Command:**
```bash
bash scripts/orchestration/hardening-master.sh --phase portal-sync
bash scripts/orchestration/hardening-master.sh --phase portal-sync --execute
```

**What It Does:**
- Checks portal health endpoint (http://localhost:5000/health)
- Checks backend health endpoint (http://localhost:3000/health)
- Validates state synchronization between services
- Checks database consistency
- Logs all checks to JSONL

**Requires:**
- Portal service running on localhost:5000
- Backend service running on localhost:3000
- curl command available

**Output:**
- Log: `logs/hardening/hardening-orchestrator-*.log`
- Errors: `logs/hardening/errors-*.jsonl`

---

### Phase 2: Test Suite Consolidation

**Purpose:** Run consolidated test suite with optimizations

**Command:**
```bash
bash scripts/orchestration/hardening-master.sh --phase test-consolidate
bash scripts/orchestration/hardening-master.sh --phase test-consolidate --execute
```

**What It Does:**
- Consolidates all test paths (backend, portal, integration, e2e)
- Runs with `--runInBand` (single process)
- Runs with `--maxWorkers=1` (memory optimization)
- Logs all test results to JSONL
- Tracks failures for analysis

**Requires:**
- npm or pnpm installed
- test:consolidated script defined in package.json
- Sufficient memory (>2GB recommended)

**Output:**
- Log: `logs/hardening/hardening-orchestrator-*.log`
- Test Results: included in JSONL logs

---

### Phase 3: Error Tracking Centralization

**Purpose:** Aggregate and analyze all system errors

**Command:**
```bash
bash scripts/orchestration/hardening-master.sh --phase error-tracking
bash scripts/orchestration/hardening-master.sh --phase error-tracking --execute
```

**What It Does:**
- Collects all JSONL error files from the system
- Aggregates into central error directory (`logs/errors/central/`)
- Analyzes error patterns and frequencies
- Creates trend analysis by timestamp
- Generates actionable recommendations

**Requires:**
- jq command installed (optional, falls back to grep)
- Existing error logs in JSONL format
- Write access to `logs/errors/central/`

**Output:**
- Aggregated Errors: `logs/errors/central/aggregate-*.jsonl`
- Analysis patterns are logged to console and main log

---

### Phase 4: Enhancement Backlog Prioritization

**Purpose:** Analyze and prioritize remaining hardening work

**Command:**
```bash
bash scripts/orchestration/hardening-master.sh --phase enhancement
bash scripts/orchestration/hardening-master.sh --phase enhancement --execute
```

**What It Does:**
- Fetches all open [Prod Hardening] issues from GitHub
- Calculates priority scores based on impact
- Generates implementation roadmap
- Outputs recommended next steps

**Requires:**
- GitHub CLI (gh) installed and authenticated
- GitHub personal access token with repo access
- Connection to github.com

**Output:**
- Issue list with priority scores
- Roadmap recommendations in console log
- Integration with `logs/hardening/hardening-orchestrator-*.log`

---

### Phase 5: Continuous Validation Framework

**Purpose:** Set up automated continuous hardening checks

**Command:**
```bash
bash scripts/orchestration/hardening-master.sh --phase monitoring
bash scripts/orchestration/hardening-master.sh --phase monitoring --execute
```

**What It Does:**
- Generates Cloud Build trigger configuration
- Creates monitoring alerts configuration
- Generates scheduled job definitions
- Creates monitoring dashboard configuration
- Outputs configuration files for manual setup

**Requires:**
- GCP project with Cloud Build enabled
- Cloud Scheduler API enabled
- Cloud Monitoring enabled
- Terraform or CLI access to deploy configs

**Output:**
- `cloudbuild-hardening.yaml` - Cloud Build pipeline config
- `config/monitoring-alerts.yaml` - Alert definitions
- `config/scheduled-jobs.yaml` - Scheduler job configs
- `config/dashboards/hardening-metrics.json` - Monitoring dashboard

**Manual Next Steps:**
1. Review generated config files
2. Deploy alerts in Cloud Console
3. Create scheduler jobs via Cloud Console or CLI
4. Deploy dashboard to Cloud Monitoring
5. Test pipeline with `gcloud builds submit --config=cloudbuild-hardening.yaml`

---

## Execution Modes

### DRY-RUN (Default - Safe)

```bash
bash scripts/orchestration/hardening-master.sh --phase all
```

- No mutations made
- All steps validated
- Full logging captured
- Safe to run repeatedly
- Ideal for testing and validation

### EXECUTE (Requires Flag)

```bash
bash scripts/orchestration/hardening-master.sh --phase all --execute
```

- Performs actual state mutations
- Aggregates real data
- Executes tests
- Modifies system state
- Use with caution

### STRICT (Early Abort)

```bash
bash scripts/orchestration/hardening-master.sh --phase all --strict
```

- Fails immediately on first error
- Default behavior: continues on non-blocking errors
- Ideal for CI/CD pipelines
- Can be combined with `--execute`

---

## Logging & Monitoring

### Log Files

All logs are JSONL-formatted for easy parsing:

```
logs/hardening/
├── hardening-orchestrator-20260314T134805Z.log    # Main execution log
├── errors-20260314T134805Z.jsonl                  # Error audit trail
└── [multiple timestamped logs for each run]

logs/errors/
└── central/
    └── aggregate-20260314T134805Z.jsonl           # Central error log

reports/hardening/
└── hardening-report-20260314T134805Z.md           # Execution summary
```

### Querying Logs

```bash
# View all errors
jq '.error' logs/hardening/errors-*.jsonl | sort | uniq -c

# Find errors by step
jq 'select(.step == "portal-sync")' logs/hardening/errors-*.jsonl

# List all log sources
ls -la logs/hardening/

# View latest report
cat reports/hardening/hardening-report-*.md | tail -20
```

### Real-Time Monitoring

```bash
# Watch orchestrator execution in real-time
tail -f logs/hardening/hardening-orchestrator-*.log

# Monitor error aggregation
watch -n 5 'wc -l logs/errors/central/*.jsonl'

# Track issue updates
gh issue list --search "[Prod Hardening] in:title"
```

---

## Email Scheduling

### Daily Hardening Cycle

```bash
# Add to crontab for daily execution
0 0 * * * cd /home/akushnir/self-hosted-runner && bash scripts/orchestration/hardening-master.sh --phase all --execute --strict >> logs/cron-hardening-daily.log 2>&1
```

### Weekly Backlog Review

```bash
# Every Monday at 9 AM
0 9 * * 1 cd /home/akushnir/self-hosted-runner && bash scripts/github/prioritize-hardening-backlog.sh --execute >> logs/cron-backlog-weekly.log 2>&1
```

### Hourly Portal Checks

```bash
# Every hour
0 * * * * cd /home/akushnir/self-hosted-runner && bash scripts/qa/portal-backend-sync-validator.sh >> logs/cron-portal-hourly.log 2>&1
```

---

## Troubleshooting

### Services Not Running

**Problem:** Portal/backend health checks fail

**Solution:**
```bash
# Start services first
docker-compose up -d portal backend

# Then run validation
bash scripts/orchestration/hardening-master.sh --phase portal-sync --execute
```

### Test Consolidation Fails

**Problem:** Test suite crashes with OOM

**Solution:**
```bash
# Run with minimal workers (already configured)
# Requires >2GB memory on runner
# Or run on high-memory machine:

gcloud compute instances create hardening-runner \
  --machine-type=n1-highmem-4 \
  --zone=us-central1-a

# Then ssh in and run:
bash scripts/orchestration/hardening-master.sh --phase test-consolidate --execute
```

### GitHub Authentication Fails

**Problem:** "gh: permission denied" or "not authenticated"

**Solution:**
```bash
# Authenticate with GitHub
gh auth login

# Provide personal access token when prompted
# Token needs: repo, read:org scopes

# Verify authentication
gh auth status
```

### Permission Denied on Logs

**Problem:** Cannot write to logs/hardening directory

**Solution:**
```bash
# Ensure directory exists and is writable
mkdir -p logs/hardening logs/errors/central reports/hardening
chmod -R 755 logs reports

# Run orchestrator again
bash scripts/orchestration/hardening-master.sh --phase all
```

---

## Best Practices

1. **Always Start with DRY-RUN**
   ```bash
   bash scripts/orchestration/hardening-master.sh --phase all
   # Review output, then add --execute if needed
   ```

2. **Monitor Logs During Execution**
   ```bash
   # In another terminal
   tail -f logs/hardening/hardening-orchestrator-*.log
   ```

3. **Review Generated Reports**
   ```bash
   cat reports/hardening/hardening-report-*.md
   ```

4. **Track GitHub Issues**
   ```bash
   # Comment on issues as phases complete
   gh issue comment [ISSUE_NUM] --body "✅ Phase 1 complete: ..."
   ```

5. **Archive Old Logs Periodically**
   ```bash
   find logs/hardening -name "*.log" -mtime +30 -exec gzip {} \;
   find logs/hardening -name "*.jsonl" -mtime +30 -exec gzip {} \;
   ```

---

## Maintenance Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| All Phases | Daily | `hardening-master.sh --phase all --execute` |
| Portal/Backend Check | Hourly | `portal-backend-sync-validator.sh` |
| Error Analysis | Daily | `--phase error-tracking --execute` |
| Backlog Review | Weekly | `prioritize-hardening-backlog.sh --execute` |
| Log Archival | Monthly | `find logs -mtime +30 -exec gzip {} \;` |
| Dashboard Update | Real-time | Monitored via Cloud Dashboards |

---

## Support & Escalation

| Issue | Contact | Reference |
|-------|---------|-----------|
| Framework Bug | GitHub Issue #3009 | Immutable/ephemeral guarantees |
| Portal Sync | GitHub Issue #3017 | Zero-drift validation |
| Test Failures | GitHub Issue #3011 | Consolidation issue |
| Error Patterns | GitHub Issue #3015 | Centralization issue |
| Backlog Items | GitHub Issue #3016 | Enhancement tracking |

---

## Related Documentation

- [Production Execution Certification](PRODUCTION_EXECUTION_CERTIFICATION_20260314.md)
- [Production Governance Closure](PRODUCTION_GOVERNANCE_CLOSURE_20260314.md)
- [Production Deployment Final](PRODUCTION_DEPLOYMENT_FINAL_20260314.md)
- [QA Production Automation Runbook](RUNBOOKS/PRODUCTION_QA_AUTOMATION_RUNBOOK.md)

---

**This runbook is the authoritative source for hardening operations. Keep it updated as new features are added.**

