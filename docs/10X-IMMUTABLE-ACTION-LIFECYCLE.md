# 10X IMMUTABLE ACTION LIFECYCLE & AUTO-FIX SYSTEM

## Overview

A production-grade system that mandates **delete-and-rebuild** for all debugged GitHub Actions, ensuring:

- ✅ **Immutable** - All actions versioned with SHA256 integrity hashes
- ✅ **Ephemeral** - Automatic state cleanup before rebuild (no carryover)
- ✅ **Idempotent** - Rebuild is deterministic from source (safe to re-run)
- ✅ **No-Ops** - All credentials via GSM/VAULT/KMS (zero plaintext)
- ✅ **Fully Automated** - GitHub Actions workflows + cron scheduling
- ✅ **Hands-Off** - Zero manual intervention, metrics-driven operations

---

## Architecture

### Core Components

#### 1. **Immutable Action Lifecycle Manager** (`immutable-action-lifecycle.py`)

Enforces delete-and-rebuild lifecycle:

```
┌─────────────────────────────────────────────────────────────┐
│  ACTION DEBUG FLAGGED                                       │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  1. VERIFY: Load existing manifest & debug cycle           │
│  2. BACKUP: Create ephemeral state backup                  │
│  3. DELETE: Wipe all action files (ephemeral)             │
│  4. REBUILD: Restore from git (idempotent)                 │
│  5. INJECT: Add credentials from GSM/VAULT/KMS            │
│  6. VALIDATE: Run tests & integrity checks                │
│  7. COMMIT: Update manifest, mark success                 │
│  8. CLEANUP: Remove backup if successful                  │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────┐
│  ACTION FRESH & IMMUTABLE (new version)                    │
└─────────────────────────────────────────────────────────────┘
```

#### 2. **Action Metadata Manifest** (`action-manifest.json`)

Stores in each action directory:

```json
{
  "version": "v1.0.1-rebuild-20260309",
  "created_at": "2026-03-09T10:30:45.123456Z",
  "debug_cycle": 2,
  "integrity_hash": "a1b2c3d4e5f6",
  "credentials_provider": "GSM/VAULT/KMS",
  "lifecycle_state": "ACTIVE",
  "ephemeral_ttl_hours": 720,
  "rebuild_checksum": null,
  "previous_versions": [
    {
      "version": "v1.0.0",
      "archived_at": "2026-03-08T15:20:10.000000Z",
      "debug_cycle": 1
    }
  ]
}
```

#### 3. **Credential Manager** (GSM/VAULT/KMS)

All credentials managed through:
- **Google Secret Manager (GSM)** - Primary provider
- **HashiCorp Vault** - Fallback/hybrid deployments
- **AWS KMS** - Encryption key management

No plaintext secrets ever stored in action files.

#### 4. **Auto-Fix Orchestrator** (`auto-fix-orchestrator.py`)

Automated cycle that:
1. Detects workflow failures (`gh run list`)
2. Scans actions for issues (YAML syntax, redacted secrets, etc.)
3. **Mandates** delete-and-rebuild for any problematic action
4. Verifies integrity post-rebuild
5. Generates audit reports

#### 5. **GitHub Actions Workflows**

Automated execution triggers:
- **Daily 2 AM UTC** - Mandatory rebuild mandate cycle
- **On failure** - Immediate action debug & rebuild flag
- **On-demand** - Manual trigger via workflow_dispatch

---

## Usage Examples

### 1. Discover All Actions

```bash
python3 scripts/immutable-action-lifecycle.py discover
```

**Output:**
```
.github/actions/docker-login
.github/actions/deploy-to-aws
.github/actions/run-tests
.github/actions/publish-release
```

### 2. Flag Action for Debug & Rebuild

```bash
python3 scripts/immutable-action-lifecycle.py debug \
  --action .github/actions/docker-login \
  --reason "Failed to authenticate: EACCES permission denied"
```

**Manifest Update:**
```json
{
  "rebuild_required": true,
  "last_debug_at": "2026-03-09T10:45:30.123456Z",
  "last_debug_reason": "Failed to authenticate: EACCES permission denied",
  "debug_cycle": 3
}
```

### 3. Rebuild Single Action

```bash
python3 scripts/immutable-action-lifecycle.py rebuild \
  --action .github/actions/docker-login
```

**Output:**
```
🔄 REBUILD CYCLE: docker-login
📦 Backed up to: .github/actions/docker-login/.backup-20260309-104530
🗑️  Deleted action state
🔄 Rebuilt from git source
🔐 Injecting credentials from GSM/VAULT/KMS
✅ Action validation passed
✅ REBUILD COMPLETE: docker-login -> v1.0.3-rebuild-20260309
```

### 4. Mandate Rebuild All Debugged Actions

```bash
python3 scripts/immutable-action-lifecycle.py mandate-all \
  --output /tmp/mandate-results.json
```

**Output:**
```json
{
  "total_actions": 12,
  "debugged_actions": ["docker-login", "deploy-to-aws"],
  "rebuilt_actions": [
    {
      "name": "docker-login",
      "version": "v1.0.3-rebuild-20260309",
      "timestamp": "2026-03-09T10:45:30.123456Z"
    },
    {
      "name": "deploy-to-aws",
      "version": "v1.0.2-rebuild-20260309",
      "timestamp": "2026-03-09T10:46:15.654321Z"
    }
  ],
  "failed_rebuilds": []
}
```

### 5. Generate Audit Report

```bash
python3 scripts/immutable-action-lifecycle.py audit \
  --output /tmp/audit-report.json
```

**Output:**
```json
{
  "timestamp": "2026-03-09T10:47:00.000000Z",
  "actions": [
    {
      "name": "docker-login",
      "version": "v1.0.3-rebuild-20260309",
      "debug_cycle": 3,
      "lifecycle_state": "ACTIVE",
      "rebuild_required": false,
      "integrity_verified": true,
      "created_at": "2026-03-05T08:00:00.000000Z",
      "rebuilt_at": "2026-03-09T10:45:30.123456Z"
    }
  ],
  "summary": {
    "total": 12,
    "active": 12,
    "rebuild_required": 0,
    "integrity_verified": 12
  }
}
```

### 6. Run Auto-Fix Orchestrator

```bash
# Dry-run (preview changes)
python3 scripts/auto-fix-orchestrator.py --dry-run --output /tmp/autofix-report.txt

# Production run (execute rebuilds)
python3 scripts/auto-fix-orchestrator.py --output /tmp/autofix-report.txt
```

---

## GitHub Actions Workflows

### Workflow: `10x-immutable-action-rebuild.yml`

**Triggers:**
- Daily 2 AM UTC (cron: `0 2 * * *`)
- Manual: `workflow_dispatch`

**Jobs:**
1. `mandate-rebuild-debugged-actions` - Run mandate cycle
2. `validate-ephemeral-cleanup` - Verify cleanup succeeded

**Environment Variables:**
```yaml
GCP_PROJECT_ID: ${{ secrets.GCP_PROJECT_ID }}
VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
AWS_KMS_KEY_ID: ${{ secrets.AWS_KMS_KEY_ID }}
```

**Required Secrets:**
- `GCP_SA_KEY` - Google Service Account for GSM
- `VAULT_TOKEN` - HashiCorp Vault authentication
- `GCP_PROJECT_ID` - GCP project for GSM

---

## Credential Management: GSM/VAULT/KMS

### Setup

#### 1. Google Secret Manager (Primary)

```bash
# Create secret for action
gcloud secrets create action-docker-login-token \
  --replication-policy="automatic" \
  --data-file=- << EOF
{"registry": "ghcr.io", "token": "..."}
EOF

# Label for action discovery
gcloud secrets update action-docker-login-token \
  --update-labels=action=docker-login
```

#### 2. HashiCorp Vault (Fallback)

```bash
# Store credentials
vault kv put secret/actions/docker-login \
  registry="ghcr.io" \
  token="..."

# Retrieve
vault kv get secret/actions/docker-login
```

#### 3. Credential Injection

When action is rebuilt, credentials are injected as:
- Environment variables (in action.yml)
- Secret files (git-ignored)
- Mounted volumes (in container actions)

**Example action.yml:**
```yaml
name: 'Docker Login'
description: 'Authenticate to Docker registry'
inputs:
  registry:
    description: 'Docker registry'
    required: false
    default: 'ghcr.io'
  token:
    description: 'Authentication token'
    required: true
runs:
  using: 'composite'
  steps:
    - shell: bash
      env:
        REGISTRY: ${{ inputs.registry }}
        TOKEN: ${{ secrets.DOCKER_TOKEN }}  # From GSM at rebuild time
      run: |
        echo $TOKEN | docker login -u $USER --password-stdin $REGISTRY
```

---

## Immutability Guarantees

### Integrity Verification

Each action has a SHA256 hash computed from its files:

```python
# Compute hash
hash = SHA256(sorted_files_in_action)
# Store in manifest
manifest['integrity_hash'] = hash[:12]
# Verify at rebuild
assert compute_hash(action_path) == manifest['integrity_hash']
```

### Version Format

```
v{MAJOR}.{MINOR}.{PATCH}-rebuild-{DATE}

Example: v1.0.3-rebuild-20260309
         └─ Major.Minor.Patch: base version
                           └─ Rebuild marker
                             └─ Date of rebuild
```

---

## Ephemeral Cleanup

### Backup Strategy

Before deletion:
```bash
.github/actions/docker-login/
├── action.yml
├── action.js
└── .backup-20260309-104530/    ← Ephemeral backup
    ├── action.yml
    └── action.js
```

### TTL Cleanup

Backups automatically cleanup:
- If rebuild **succeeds**: Backup deleted immediately
- If rebuild **fails**: Backup retained for rollback
- Stale backups (>7 days): Automated cleanup

### Validation

```bash
# Verify no stale backups
find .github/actions -type d -name '.backup-*' -mtime +7
# Should output: [empty]
```

---

## Idempotency Guarantees

All rebuild operations are **deterministic and idempotent**:

```
RUN: rebuild --action docker-login
↓
Step 4: REBUILD from git checkout
$ git checkout HEAD -- .github/actions/docker-login
↓
Result: Identical to previous rebuild ✅
Can be safely re-run multiple times
```

---

## No-Ops Automation

### Fully Hands-Off Execution

**No manual intervention required:**
- ❌ No SSH access needed
- ❌ No credential entry
- ❌ No file edits
- ❌ No approval gates (except for high-risk repairs)
- ✅ All from CI/CD automation
- ✅ All credentials from GSM/VAULT/KMS

### Scheduled Execution

```
Monday    2 AM → Mandate rebuild
Monday    3 AM → Credential rotation
Monday    4 AM → Compliance audit
...
```

---

## Audit Logging

### Immutable Append-Only Log

File: `.github/.immutable-audit.log`

```json
{"timestamp": "2026-03-09T10:30:45Z", "action": "action_flagged_for_debug", "details": {"action_name": "docker-login", "reason": "auth_failure"}}
{"timestamp": "2026-03-09T10:45:30Z", "action": "action_rebuilt", "details": {"action_name": "docker-login", "issues": ["redacted_secrets"]}}
{"timestamp": "2026-03-09T10:47:00Z", "action": "auto_fix_cycle_complete", "details": {"cycle_id": "20260309-104700", "actions_rebuilt": 2}}
```

**Properties:**
- Append-only (no deletion)
- JSON format (machine-readable)
- Timestamped (chronological)
- Immutable (once written, never modified)
- 365-day retention
- AES-256 encryption at rest

### Query Audit Log

```bash
# Show all action rebuilds
grep '"action": "action_rebuilt"' .github/.immutable-audit.log | jq '.details'

# Show failure counts by day
grep '"action"' .github/.immutable-audit.log | \
  cut -d'T' -f1 | sort | uniq -c
```

---

## Metrics & Dashboards

### Key Metrics

1. **Rebuild Velocity** - Actions rebuilt per day
2. **Integrity Score** - Percentage of verified actions
3. **Failure Rate** - Failed rebuilds / total rebuilds
4. **MTTR** - Mean time to rebuild after debug flag
5. **Credential Rotation** - GSM/VAULT/KMS secret updates

### Example Dashboard Query

```
SELECT
  DATE(timestamp) as date,
  COUNT(CASE WHEN action = 'action_rebuilt' THEN 1 END) as rebuilt_count,
  COUNT(CASE WHEN action = 'rebuild_failed' THEN 1 END) as failed_count
FROM ( SELECT * FROM `.github/.immutable-audit.log` )
GROUP BY DATE(timestamp)
ORDER BY date DESC
```

---

## Integration Checklist

- [ ] Create `.github/workflows/10x-immutable-action-rebuild.yml`
- [ ] Copy `scripts/immutable-action-lifecycle.py`
- [ ] Copy `scripts/auto-fix-orchestrator.py`
- [ ] Add repository secrets:
  - [ ] `GCP_SA_KEY` (Google Service Account)
  - [ ] `VAULT_TOKEN` (HashiCorp Vault)
  - [ ] `GCP_PROJECT_ID` (Google Cloud Project)
- [ ] Create initial action manifests (`action-manifest.json`)
- [ ] Test dry-run: `python3 scripts/auto-fix-orchestrator.py --dry-run`
- [ ] Configure GitHub Actions secrets for credential access
- [ ] Schedule workflow: Daily 2 AM UTC

---

## Troubleshooting

### Action Rebuild Failed

```bash
# Check logs
cat .github/.immutable-audit.log | tail -20

# Verify action syntax
python3 -c "import yaml; yaml.safe_load(open('.github/actions/docker-login/action.yml'))"

# Try manual rebuild with verbose output
python3 scripts/immutable-action-lifecycle.py rebuild \
  --action .github/actions/docker-login 2>&1 | tee /tmp/rebuild.log
```

### Credentials Not Injected

```bash
# Verify GSM access
gcloud secrets list --project=$GCP_PROJECT_ID

# Verify Vault access
vault kv list secret/actions/

# Check credential file was created
ls -la .github/actions/docker-login/.action-secrets.env
```

### Integrity Check Failed

```bash
# Recompute hash
python3 << 'EOF'
import hashlib
from pathlib import Path

action_path = '.github/actions/docker-login'
hasher = hashlib.sha256()

for file in sorted(Path(action_path).rglob('*')):
    if file.is_file() and not file.name.startswith('.'):
        with open(file, 'rb') as f:
            hasher.update(f.read())

print(f"Current hash: {hasher.hexdigest()[:12]}")

import json
with open(f'{action_path}/action-manifest.json') as f:
    manifest = json.load(f)
    print(f"Stored hash:  {manifest['integrity_hash']}")
EOF

# If mismatch, action was modified: trigger rebuild
python3 scripts/immutable-action-lifecycle.py rebuild --action .github/actions/docker-login
```

---

## Related Documentation

- [ADR-0001: Autonomous Pipeline Repair](./docs/adr/ADR-0001-autonomous-pipeline-repair.md)
- [GIT_GOVERNANCE_STANDARDS.md](./GIT_GOVERNANCE_STANDARDS.md)
- [GSM AWS Credentials Architecture](./GSM_AWS_CREDENTIALS_ARCHITECTURE.md)
