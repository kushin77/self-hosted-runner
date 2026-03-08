# Workflow Consolidation Guards & Audit System

This directory contains the immutable audit trail, state checkpoints, and guard configurations for the workflow consolidation orchestration system.

## Directory Structure

```
.audit-logs/
├── consolidation-audit.log    # Immutable append-only audit trail
├── *.log                       # Per-execution audit logs (auto-cleanup after 30 days)
└── execution-reports/         # Timestamped execution reports

.workflow-state/
├── consolidation.state        # Idempotent checkpoint (last completed phase, merged count)
├── consolidation.lock         # Ephemeral lock file (TTL: 1 hour)
└── last-state-hash            # SHA256 of workflow files (for deduplication)
```

## Guarantees

### 🔒 Immutable
- All changes audit-logged with execution ID, timestamp, actor, and SHA
- Append-only logs (no deletions, only archival)
- 30-day retention minimum
- Complete transaction history preserved

### 🌊 Ephemeral
- Temporary resources auto-cleanup after TTL (1 hour)
- Lock files removed if execution completes or times out
- Temp workflows (.workflow-state/temp-*.yml) deleted after 1 day
- Cloud credentials used with minimal lifetime (GitHub Actions 1 hour, GSM federated, VAULT short-lived)

### 🔄 Idempotent
- State checksum (SHA256) prevents duplicate runs
- Last-completed-phase checkpoint allows safe resume
- Deduplication window (5 minutes) coalesces burst executions
- Each workflow checked for "already completed" state before execution

### 🤖 No-Ops (Hands-Off)
- Zero manual approvals required
- Fully scheduled (daily 2 AM UTC) or manually triggered via workflow_dispatch
- Autonomous orchestration of reusable workflows
- Automatic rollback-only on critical failures

## Key Files & Purposes

| File | Purpose | TTL | Format |
|------|---------|-----|--------|
| `consolidation.state` | Phase checkpoints + merged count | Permanent | bash env |
| `consolidation.lock` | Execution lock (prevents race) | 1 hour | file existence |
| `last-state-hash` | Workflow files checksum | Permanent | hex string |
| `*.log` in audit-logs | Per-execution audit trail | 30 days | JSON |

## Multi-Layer Credential Strategy

### Priority Order
1. **Google Secrets Manager (GSM)** — Federated identity, workload identity, ephemeral tokens
2. **HashiCorp Vault** — Auto-rotating secrets, audit logging, fine-grained policies
3. **AWS KMS** — Encrypted credential storage, envelope encryption, access logs
4. **GitHub Secrets** — Fallback, 1-hour token lifetime, GITHUB_TOKEN

### Credential Rotation
- **Interval**: Every 7 days (configurable via `CREDENTIAL_ROTATION_INTERVAL`)
- **Auto-Rotate**: Triggered by `secret-rotation-reusable.yml`
- **Audit Trail**: All rotation events logged to immutable audit trail
- **Failover**: Automatic failover to next tier on layer failure

## Usage

### Manual Trigger (Dry-Run)
```bash
gh workflow run 01-workflow-consolidation-orchestrator.yml \
  --field dry_run='true' \
  --field target_phase='all'
```

### Manual Trigger (Execute)
```bash
gh workflow run 01-workflow-consolidation-orchestrator.yml \
  --field dry_run='false' \
  --field target_phase='security'  # or 'features', 'docs', 'all'
```

### Check Audit Trail
```bash
cat .audit-logs/consolidation-audit.log
```

### Resume from Checkpoint
```bash
source .workflow-state/consolidation.state
echo "Last phase: $LAST_COMPLETED_PHASE"
echo "Merged: $MERGED_COUNT"
```

## Monitoring & Alerting

### Health Checks
```bash
# Check if consolidation is in-flight
test -f .workflow-state/consolidation.lock && echo "In-flight" || echo "Idle"

# View last execution
tail -20 .audit-logs/consolidation-audit.log

# Check credential rotation status
grep -i "credential.*rotation" .audit-logs/consolidation-audit.log | tail -1
```

### Stale Resource Detection
- Consolidation locks older than 1 hour → Auto-removed, issue created
- Audit logs older than 30 days → Auto-archived
- State checksum unchanged for 14+ days → Issue flagged for review

## Troubleshooting

### Consolidation Stuck (Lock File Present)
```bash
# Check lock file age
stat .workflow-state/consolidation.lock | grep Modify

# If >1 hour old, safe to remove
rm .workflow-state/consolidation.lock
```

### Credential Rotation Failed
```bash
# Check active credential layer fallback
grep "active_layer" .audit-logs/consolidation-audit.log | tail -1

# Manually trigger rotation
gh workflow run secret-rotation-reusable.yml --field auto_rotate='true'
```

### Resume from Failure
1. Check `.audit-logs/` for root cause
2. Manual fix as needed (if any)
3. Reset state checkpoint: `rm .workflow-state/consolidation.state`
4. Re-trigger: The orchestrator will resume from phase 0
