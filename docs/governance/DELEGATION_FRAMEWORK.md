# Delegation Framework - Trusted Authority Model

**Status:** ✅ ACTIVE | **Version:** 1.0 | **Last Updated:** 2026-03-11

---

## 🎯 Delegation Principles

1. **Explicit Delegation** — Authority granted only via recorded delegation token
2. **Scoped Authority** — Each delegation valid for specific operation + time window
3. **Revocable** — Any delegation can be revoked immediately
4. **Observable** — All delegations logged with approval context
5. **Auditable** — Delegation chain traceable via immutable records

---

## 🔐 Delegation Token Structure

```bash
# Format: DLG-{role}-{nonce}-{timestamp}-{expiry}-{signature}
DLG-CredentialManager-abc123-2026-03-11T12:00:00Z-2026-03-11T13:00:00Z-sig_xyz789
  │     │                │     │                 │                 │
  │     │                │     │                 │                 └─ Cryptographic signature
  │     │                │     │                 └─ Expiry (absolute deadline)
  │     │                │     └─ Issued timestamp
  │     │                └─ Nonce (prevents reuse)
  │     └─ Authorized role
  └─ Token type prefix
```

---

## 📋 Delegation Scenarios

### Scenario 1: Regular Secret Rotation (No Escalation)
```
Actor: Credential Manager Service Account
Requested by: System (Cron Job @ 2 AM UTC)
Delegation Flow:
  1. Cron triggers rotation script
  2. Script requests delegation token from RBAC manager
  3. RBAC checks: Role="Cred Mgr", Capability="rotate_secrets" ✓
  4. Issues time-bound token (valid 1 hour)
  5. Script uses token to call rotate-credentials.sh
  6. Script logs delegation token + operation result
  7. Token auto-expires after 1 hour
  8. Audit record: { actor, delegation_id, operation, result, timestamp }

Approval Required: ZERO (routine operation)
Audit Trail: Automatic (logged by system)
```

### Scenario 2: Emergency Secret Access (Escalation)
```
Actor: Developer (typically no secret access)
Requested by: Developer via CLI (justification required)
Delegation Flow:
  1. Developer runs: nexus-cli access-secret --reason "database_migration_debug"
  2. System routes to Security Architect + Compliance Officer
  3. Both review: motivation, scope, duration
  4. Both approve → system issues time-bound delegation token
  5. Token valid for 5 minutes only
  6. Developer can read secret once during window
  7. Token auto-revokes after 5 minutes
  8. Audit: { requester, approvers, justification, access_time, revocation_time }

Approval Required: TWO (escalated)
Duration: 5 minutes (hard stop)
Scope: Single secret read
Post-Access Review: Automatic (within 1 hour)
```

### Scenario 3: Production Deployment (Staged Approval)
```
Actor: Deployment Engineer
Requested by: Staging environment auto-validation passed
Delegation Flow:
  Stage 1 - Pre-Deployment Check
    → Compliance Officer validates: staging tests ✓, security scan ✓, audit ok ✓
    → Issues "pre_deploy_delegation" token (valid 1 hour)

  Stage 2 - Deployment Execution
    → Deployment Engineer uses pre_deploy token
    → System validates: role ✓, token ✓, rate limit ✓
    → Issues "deploy_execute_delegation" token (valid 15 minutes)
    → Deployment proceeds with full logging

  Stage 3 - Post-Deployment Verification
    → Health checks run automatically
    → If healthy: soft close (logged)
    → If unhealthy: hard stop + auto-rollback + alert

Approval Required: ONE (delegated by Compliance)
Execution Window: 15 minutes
Audit Trail: Every delegation + execution step logged
```

---

## 🔄 Delegation State Machine

```
CREATED → APPROVED → ACTIVE → [USED/UNUSED] → EXPIRED/REVOKED
   │         │          │            │            │
   │         │          │            │            └─ Final state
   │         │          │            └─ Can transition to: EXPIRED, REVOKED
   │         │          └─ Active window (request must occur)
   │         └─ Awaiting explicit approval
   └─ Initial state (pending approval check)
```

---

## 📝 Delegation Lifecycle

### Creation
```bash
# System creates delegation token
nexus-delegation create \
  --role "Credential Manager" \
  --capability "rotate_secrets" \
  --duration "3600s" \
  --justification "scheduled_rotation" \
  --approvers "security-architect@company.com"
```

### Approval (if required)
```bash
# Approver grants delegation
nexus-delegation approve \
  --token "DLG-CredentialManager-abc123-..." \
  --approver "security-architect@company.com" \
  --comment "rotation_approved_per_policy"
```

### Usage
```bash
# Actor uses delegation to perform operation
export NEXUS_DELEGATION="DLG-CredentialManager-abc123-..."
./scripts/secrets/rotate-credentials.sh --apply
```

### Verification
```bash
# System verifies token before operation
nexus-delegation verify \
  --token "DLG-CredentialManager-abc123-..." \
  --operation "rotate_secrets" \
  --timestamp "2026-03-11T12:30:45Z"
```

### Expiration
```bash
# Token auto-expires after deadline
# Expired tokens cannot be used
# System logs: { token_id, expiry_time, usage_count, final_status }
```

---

## 🚨 Delegation Violations

| Violation | Trigger | Action |
|---|---|---|
| **Unauthorized Use** | Token used by non-authorized role | DENY + REVOKE + escalate |
| **Reuse Attack** | Same token used twice | DENY + REVOKE + investigate |
| **Expired Token** | Token used after expiry | DENY + log attempt |
| **Forgery Attempt** | Signature validation fails | DENY + security alert |
| **Scope Violation** | Token used for different operation | DENY + escalate |
| **Rate Limit Exceeded** | Too many tokens issued to role (>10/min) | THROTTLE + investigate |

---

## 📊 Delegation Audit Format

```json
{
  "delegation_id": "DLG-CredentialManager-abc123-2026-03-11T12:00:00Z-2026-03-11T13:00:00Z",
  "event": "delegation_created",
  "role": "Credential Manager",
  "capability": "rotate_secrets",
  "issued_by": "system@nexusshield",
  "approved_by": ["security-architect@company.com"],
  "created_at": "2026-03-11T12:00:00Z",
  "expires_at": "2026-03-11T13:00:00Z",
  "used_at": "2026-03-11T12:15:32Z",
  "used_by": "sa-credential-manager@project.iam.gserviceaccount.com",
  "operation_result": "SUCCESS",
  "revoked_at": null,
  "revoke_reason": null,
  "audit_trail": [
    { "timestamp": "2026-03-11T12:00:00Z", "event": "created" },
    { "timestamp": "2026-03-11T12:00:15Z", "event": "approved", "approver": "security-architect@company.com" },
    { "timestamp": "2026-03-11T12:15:32Z", "event": "used", "result": "SUCCESS" },
    { "timestamp": "2026-03-11T13:00:00Z", "event": "expired" }
  ]
}
```

---

## ✅ Compliance Guarantee

- ✅ All authority delegated explicitly
- ✅ All delegations time-bound
- ✅ All delegations immutably logged
- ✅ All uses verified before execution
- ✅ All violations automatically detected
- ✅ Zero implicit permissions granted
- ✅ Full audit trail maintained (10 years)
