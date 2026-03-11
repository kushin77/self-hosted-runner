# Enterprise RBAC Matrix - Role-Based Access Control

**Status:** ✅ ACTIVE | **Version:** 1.0 | **Last Updated:** 2026-03-11

---

## 📋 Role Hierarchy

```
ROOT/Admin (Emergency Override Only)
├── Security Architect (Policy Definition, Audit)
├── Deployment Engineer (Production Operations)
├── Credential Manager (Secret Lifecycle)
├── Compliance Officer (Audit, Reporting)
├── Developer (Code Submission, Testing)
└── Observer (Read-Only Audit)
```

---

## 🔐 Capability Matrix: Who Can Do What

| Capability | Admin | Sec Architect | Deploy Eng | Cred Mgr | Compliance | Developer | Observer |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Create Secrets** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Rotate Secrets** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Delete Secrets** | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Mirror Secrets** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Deploy to Prod** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Deploy to Staging** | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ |
| **Deploy to Dev** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **Approve Policy** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Override Governance** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **View Audit Logs** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| **Export Audit Logs** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Modify Governance** | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Access Service Account** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |

---

## 🎯 Approval Chain by Operation

### Secret Operations
**Create/Delete:** Credential Manager OR Security Architect (1 approval minimum)  
**Rotate:** Credential Manager OR Security Architect (1 approval minimum)  
**Emergency Rotate:** Admin (immediate, logged)  

### Deployment Operations
**Prod Deploy:** Deployment Engineer + Compliance Officer (2 approvals)  
**Staging Deploy:** Deployment Engineer OR Security Architect (1 approval)  
**Dev Deploy:** Self-service (0 approvals, logged)  

### Policy Changes
**Create Policy:** Security Architect (proposal)  
**Approve Policy:** Security Architect + Compliance Officer (2 approvals)  
**Activate Policy:** Admin OR Security Architect (1 approval)  
**Emergency Override:** Admin only (auto-audit, requires executive sign-off within 24h)  

---

## 🔑 Service Account Assignments

| Service Account | Role | Capabilities | Backend |
|---|---|---|---|
| `nexusshield-ci` | Deploy Eng | Deploy staging/dev, mirror secrets | GSM/Vault/KMS |
| `nexusshield-prod` | Deploy Eng | Deploy prod, mirror secrets | GSM/Vault/KMS |
| `nexusshield-audit` | Compliance | Read audit logs, export reports | GCS/GitHub |
| `nexusshield-secrets-mgmt` | Cred Mgr | Create/rotate/delete secrets | GSM/Vault/KMS |
| `nexusshield-observer` | Observer | Read-only audit access | GitHub/Audit Logs |

---

## 📝 Credential Access Patterns

### Multi-Layer Fallback (Zero-Trust Validation)

```
Request Credential
    ↓
[LSA] Check Role Capability
    ↓ (DENY if not authorized)
[Freshness] Check TTL (max 1h for creds)
    ↓ (ROTATE if stale)
[Verification] Cryptographic signature check
    ↓ (FAIL if tampered)
[Rate Limit] Check request rate (max 10/min per role)
    ↓ (THROTTLE if exceeded)
[Audit Log] Record access with context
    ↓
GRANT Access
    ↓
[Duration] Set context timeout (5 min execution window)
```

---

## 🚨 Violation Handling

| Violation | Detection | Auto-Response | Notification |
|---|---|---|---|
| Unauthorized capability use | Pre-flight check | DENY + log | Immediate |
| Stale credential access | Freshness check | ROTATE + re-grant | 5 min alert |
| Tampered secret | Signature verify | QUARANTINE | Immediate |
| Rate limit exceeded | Per-role counter | THROTTLE (exponential backoff) | Per-violation |
| Policy override attempted | Semantic validation | DENY + escalate | Executive alert |
| Service account compromise | Anomaly detection | AUTO-DISABLE + rotate all keys | Immediate + Audit |

---

## 🔄 Time-Bound Access

- **Credential Access Window:** 5 minutes per operation
- **Deployment Window:** 15 minutes per deployment
- **Policy Review Window:** 48 hours
- **Secret Rotation Window:** 30 days (max age before forced rotation)
- **Access Log Retention:** 10 years (immutable)

---

## 📊 Audit Trail Format

Every operation logged with:
```json
{
  "timestamp": "2026-03-11T12:34:56Z",
  "operation": "secret_access",
  "role": "Credential Manager",
  "actor": "service-account@project.iam.gserviceaccount.com",
  "resource": "db-password",
  "action": "read",
  "result": "GRANTED",
  "duration_ms": 234,
  "evidence": {
    "capability_check": "PASS",
    "freshness_check": "PASS (TTL: 3600s remaining)",
    "signature_verify": "PASS",
    "rate_limit_check": "PASS (2/10 requests)"
  },
  "context": {
    "ip_address": "10.0.0.1",
    "user_agent": "nexusshield-cli/2.1",
    "correlation_id": "req-xyz-789"
  }
}
```

---

## ✅ Compliance Attestation

- ✅ All operations require explicit capability grant
- ✅ Multi-layer verification before access
- ✅ Immutable audit trail
- ✅ Time-bound access windows
- ✅ Automated violation detection
- ✅ Zero-standing credentials (all time-bound)
- ✅ No implicit trust (verify every request)
