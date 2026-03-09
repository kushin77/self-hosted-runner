# Audit Trail & Compliance Guide
**Last Updated:** 2026-03-09  
**Audience:** Security, Compliance, Audit Team  
**Data Classification:** Internal - Confidential

---

## Table of Contents
1. [Audit Trail Overview](#audit-trail-overview)
2. [Log Format & Structure](#log-format--structure)
3. [Querying the Audit Trail](#querying-the-audit-trail)
4. [Compliance Mappings](#compliance-mappings)
5. [Data Retention & Archival](#data-retention--archival)
6. [Integrity Verification](#integrity-verification)
7. [Export & Reporting](#export--reporting)

---

## Audit Trail Overview

### Core Guarantees
- **Immutable:** Append-only, no deletion/modification possible
- **Complete:** Every credential operation logged
- **Tamper-proof:** SHA-256 cryptographic hash chain
- **Traceable:** Session ID + timestamp + actor on every entry
- **Compliant:** SOC 2 Type II, ISO 27001 capable, PCI-DSS ready
- **Retention:** 365+ days (configurable, default 7+ years for compliance)

### What Gets Logged

**✅ Logged:**
- Credential retrieval (provider, key, success/failure)
- Credential rotation (start, end, result)
- Health checks (provider status, timestamp, result)
- Policy violations (blocked commits, unauthorized access attempts)
- Manual operations (override codes, emergency procedures)
- System events (startup, shutdown, corruption detection)

**❌ NOT Logged (Security):**
- Actual credential values (VAULT_TOKEN, private keys, etc.)
- Session tokens (GitHub ACTIONS_ID_TOKEN)
- Personal user data (names, emails)
- Debugging details that expose internals

### Log Location
```bash
.audit-logs/                      # Main audit directory
  ├── audit-20260309.jsonl        # Daily rotation (immutable)
  ├── audit-20260308.jsonl        # Previous day
  ├── audit-20260307.jsonl        # etc...
  └── .hash-chain-index           # Hash chain verification index
```

---

## Log Format & Structure

### Entry Structure (JSONL Format)
Each line is a complete JSON object:

```json
{
  "timestamp": "2026-03-09T14:23:45.123Z",
  "session_id": "run-12345-f23114de6",
  "operation": "credential_rotation",
  "status": "success",
  "provider": "gsm",
  "details": {
    "gcp_project": "prod-credentials",
    "secret_key": "github-oidc-token",
    "ttl_seconds": 3600,
    "attempt_number": 1
  },
  "metrics": {
    "duration_ms": 234,
    "cache_hit": false
  },
  "hash": "sha256:abc123def456...",
  "previous_hash": "sha256:xyz789..."
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | ISO-8601 | UTC timestamp of operation |
| `session_id` | String | Unique identifier for this execution |
| `operation` | String | Type: `credential_rotation`, `credential_fetch`, `health_check`, `audit_verify`, `policy_violation`, `manual_override` |
| `status` | String | `success`, `failure`, `partial`, `degraded` |
| `provider` | String | `gsm`, `vault`, `kms`, `system` |
| `details` | Object | Rich context (varies by operation) |
| `metrics` | Object | Performance/diagnostic data |
| `hash` | String | SHA-256 of this entry |
| `previous_hash` | String | SHA-256 of previous entry (chain) |

### Example Entries

**Successful Rotation:**
```json
{
  "timestamp": "2026-03-09T14:15:00Z",
  "session_id": "run-12345-rotation",
  "operation": "credential_rotation",
  "status": "success",
  "provider": "gsm",
  "details": {
    "providers_attempted": ["gsm", "vault", "kms"],
    "providers_succeeded": ["gsm"],
    "cache_updated": true
  },
  "metrics": {
    "total_duration_ms": 456,
    "gsm_duration_ms": 234
  },
  "hash": "sha256:a1b2c3...",
  "previous_hash": "sha256:z9y8x7..."
}
```

**Provider Failure with Failover:**
```json
{
  "timestamp": "2026-03-09T14:30:15Z",
  "session_id": "run-54321-rotation",
  "operation": "credential_fetch",
  "status": "success",
  "provider": "vault",
  "details": {
    "primary_provider": "gsm",
    "primary_status": "down",
    "failover_provider": "vault",
    "reason": "Network timeout after 30s"
  },
  "metrics": {
    "failover_depth": 2,
    "total_retries": 3
  },
  "hash": "sha256:d4e5f6...",
  "previous_hash": "sha256:a1b2c3..."
}
```

---

## Querying the Audit Trail

### Basic Query: All Operations Today
```bash
grep "2026-03-09" .audit-logs/audit-20260309.jsonl | head -20
```

### Advanced Query: Credential Rotations Only
```bash
grep '"operation":"credential_rotation"' .audit-logs/*.jsonl
```

### Query by Status: All Failures
```bash
grep '"status":"failure"' .audit-logs/*.jsonl | jq '.timestamp, .details'
```

### Query by Provider: All GSM Operations
```bash
grep '"provider":"gsm"' .audit-logs/*.jsonl | jq '{timestamp, operation, status}'
```

### Timeline: Last 24 Hours
```bash
# Show all operations in last 24 hours with timing
jq 'select(.timestamp > "2026-03-08T14:30:00Z") | 
    {timestamp, operation, status, provider, duration_ms: .metrics.duration_ms}' \
    .audit-logs/audit-20260309.jsonl
```

### Failover Analysis: When did we use Vault?
```bash
grep '"failover_provider":"vault"' .audit-logs/*.jsonl | wc -l
# Output: 3 failovers to Vault in last X days
```

### Compliance Queries

**Question:** How many times were credentials accessed in the last 30 days?
```bash
find .audit-logs -name "*.jsonl" -mtime -30 -exec \
  grep '"operation":"credential_fetch"' {} \; | wc -l
```

**Question:** Any policy violations in the last 7 days?
```bash
find .audit-logs -name "*.jsonl" -mtime -7 -exec \
  grep '"operation":"policy_violation"' {} \; | jq '.details'
```

**Question:** What's the availability of each provider (last 30 days)?
```bash
grep '"operation":"health_check"' .audit-logs/*.jsonl | \
  jq '.provider, .status' | sort | uniq -c

# Example output:
# 720 "gsm"
# 720 "vault"
# 720 "kms"
# (each provider health-checked hourly for 30 days = 720 checks)
```

---

### Using the Python Audit Tool

**Verify integrity:**
```bash
python3 scripts/immutable-audit.py verify
# Output: "✓ Hash chain valid (12345 entries, 30 days)"
```

**Query operations:**
```bash
python3 scripts/immutable-audit.py query --operation credential_rotation \
  --provider gsm --status success
# Output: List of all successful GSM rotations
```

**Generate report:**
```bash
python3 scripts/immutable-audit.py report --format json \
  --start-date 2026-02-09 --end-date 2026-03-09 \
  --operation credential_rotation
```

---

## Compliance Mappings

### SOC 2 Type II Compliance

| SOC 2 Requirement | How Audit Trail Satisfies |
|------------------|---------------------------|
| **CC6.1:** Authorization | Session ID + timestamp tied to each operation |
| **CC7.1:** System changes logged | Every credential operation, rotation, failure logged |
| **CC7.2:** Logging configured | 365-day retention, immutable format |
| **CC7.3:** Potential security events | All failures, retries, policy violations captured |
| **CC7.4:** Audit analysis | Hash chain enables tamper detection |
| **CC8.1:** Change detection | Before/after snapshots in historical audit trail |
| **A1.2:** Confidentiality | Credentials never logged, only metadata |

### ISO 27001 Compliance

| ISO 27001 Control | Mapping |
|------------------|---------|
| **A.12.4.1:** Recording user activity | ✓ Every operation logged with session ID |
| **A.12.4.3:** Protection of logs | ✓ Immutable append-only format |
| **A.12.4.4:** Administrator activity | ✓ Manual overrides logged with intent |
| **A.13.1.2:** Change log | ✓ Credential rotation lifecycle tracked |
| **A.13.2.3:** Cryptographic integrity | ✓ SHA-256 hash chain for detection |

### PCI-DSS Compliance (Level 1)

| Requirement | Audit Trail Evidence |
|---|---|
| **10.1:** Individual user identity | Session ID + timestamp per operation |
| **10.2:** User actions | Full credential rotation lifecycle |
| **10.3:** Privileged access | Manual overrides always logged |
| **10.4:** Invalid access attempts | Failures + retries + policy violations |
| **10.6.2:** User activity review | `immutable-audit.py report` generates required reports |
| **10.7:** Log retention 1+ year | Configured 365+ day retention |

---

## Data Retention & Archival

### Automatic Retention

```
Creation Date      → Retention Period → Auto-Archive
T (today)          → 30 days live      → In .audit-logs/
T - 30 days        → 335 days archive  → Daily compressed git commit
T - 365 days       → Deleted           → (After 365 days)
```

### Manual Archival
```bash
# Create quarterly archive (recommended for compliance)
tar --create \
  --gzip \
  --file audit-archive-Q1-2026.tar.gz \
  .audit-logs/

# Upload to cold storage (S3 Glacier, GCS Coldline, etc.)
aws s3 cp audit-archive-Q1-2026.tar.gz \
  s3://company-compliance-archive/audit-trails/2026-Q1/

# Verify integrity before deletion
python3 scripts/immutable-audit.py verify < \
  <(tar -xzOf audit-archive-Q1-2026.tar.gz .audit-logs/audit-*.jsonl)
```

### Regulatory Hold
```bash
# If under regulatory investigation, set immutable flag
chattr +i .audit-logs/audit-*.jsonl  # Linux (immutable)
# OR
chmod 000 .audit-logs/                # Universal (deny all access)

# Document in compliance log
python3 scripts/immutable-audit.py --operation "regulatory_hold" \
  --details "Legal case #XXXX - audit trail preserved"
```

---

## Integrity Verification

### Hash Chain Format

Each entry builds on prior hash:

```
Entry 1:  hash = SHA256(operations + timestamp + session)
Entry 2:  hash = SHA256(operations + timestamp + session + Entry1.hash)
Entry 3:  hash = SHA256(operations + timestamp + session + Entry2.hash)
...
```

### Verification Command

```bash
python3 scripts/immutable-audit.py verify

# Output:
# ✓ Hash chain valid (12345 entries)
# ✓ Integrity span: 2025-12-30 to 2026-03-09 (70 days)
# ✓ No corrupted entries detected
# ✓ 12,345 total operations logged
```

### Detecting Tampering

If any entry is modified, hash chain breaks:

```
Entry 2 tampered: hash mismatch detected
│
├─ Entry 2 current hash: abc123
├─ Entry 2 expected hash (from Entry 3 previous_hash): def456
└─ RESULT: ✗ Hash chain broken at entry 2
```

---

## Export & Reporting

### Generate Daily Report
```bash
python3 scripts/immutable-audit.py report \
  --format csv \
  --output audit-report-$(date +%Y%m%d).csv \
  --start-date $(date -d '1 day ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d)
```

### Generate Compliance Report (Monthly)
```bash
python3 scripts/immutable-audit.py report \
  --format dashboard \
  --output audit-compliance-$(date +%Y-%m).html \
  --metrics \
    availability \
    failure-rate \
    mttf \
    mttr
```

### Export for External Audit
```bash
# Package all logs + verification
tar -czf audit-export-SOC2.tar.gz \
  .audit-logs/ \
  <(python3 scripts/immutable-audit.py verify) \
  docs/AUDIT_TRAIL.md

# Provide to external auditor (read-only)
chmod 444 audit-export-SOC2.tar.gz
# Share via secure channel (Google Drive, Sharepoint, etc.)
```

---

## Queries for Common Investigations

### "How many times did we rotate credentials last month?"
```bash
grep '"operation":"credential_rotation"' .audit-logs/*.jsonl | \
  grep "2026-02" | wc -l
```

### "When did GSM last fail?"
```bash
grep '"provider":"gsm"' .audit-logs/*.jsonl | \
  grep '"status":"failure"' | tail -1 | jq '.timestamp'
```

### "What's our credential rotation failure rate?"
```bash
TOTAL=$(grep '"operation":"credential_rotation"' .audit-logs/*.jsonl | wc -l)
FAILURES=$(grep '"operation":"credential_rotation"' .audit-logs/*.jsonl | \
  grep '"status":"failure"' | wc -l)
echo "Failure rate: $((FAILURES * 100 / TOTAL))%"
```

### "Which provider had the most uptime?"
```bash
for provider in gsm vault kms; do
  TOTAL=$(grep "\"provider\":\"$provider\"" .audit-logs/*.jsonl | wc -l)
  SUCCESS=$(grep "\"provider\":\"$provider\"" .audit-logs/*.jsonl | \
    grep '"status":"success"' | wc -l)
  echo "$provider: $((SUCCESS * 100 / TOTAL))%"
done
```

---

## Compliance Attestation

**To generate compliance attestation:**

```bash
# 1. Verify audit trail integrity
python3 scripts/immutable-audit.py verify > attestation.txt

# 2. Generate metrics report
python3 scripts/immutable-audit.py report --format text >> attestation.txt

# 3. Sign (if using GPG)
gpg --sign attestation.txt

# 4. Submit to audit team
# File: attestation.txt.gpg (GPG-signed)
```

---

**Version:** 1.0  
**Last Updated:** 2026-03-09  
**Next Review:** 2026-04-09
