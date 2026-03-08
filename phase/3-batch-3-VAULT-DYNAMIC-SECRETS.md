# Phase 3 Batch 3: VAULT Dynamic Secrets & AppRole Operations

**Status:** Framework ready  
**Dependencies:** Phase 3 Batch 2 (KMS integration)  
**Timeline:** Auto-activate post-Batch 2 merge  

---

## Strategy

### VAULT Integration Layers
1. **Static Secrets:** Stored in VAULT (via KMS encryption at rest)
2. **Dynamic Secrets:** Generated on-demand (SSH, database, AWS credentials)
3. **AppRole Auth:** Non-human authentication for workflows
4. **Audit Logging:** All access logged to VAULT audit backend

### Implementation Plan
- Use HashiCorp VAULT for long-term secret storage
- AppRole for workflow authentication (GitHub Actions)
- Dynamic SSH credentials for runner access
- Database credentials for terraform/operations
- Secret rotation policies configured in VAULT

---

## Batch 3 Components

### 1. VAULT Configuration
- `scripts/ops/vault_login_approle.sh` — AppRole authentication
- `scripts/ops/vault_gen_dynamic_ssh.sh` — SSH secret generation
- `scripts/ops/vault_renew_lease.sh` — Lease renewal

### 2. Workflows
- `.github/workflows/vault-approle-auth.yml` — VAULT authentication
- `.github/workflows/vault-dynamic-ssh.yml` — Dynamic SSH secrets
- `.github/workflows/vault-secret-rotation.yml` — Secret rotation

### 3. Documentation
- `docs/VAULT_OPERATIONS.md` — VAULT setup & operations guide
- `docs/VAULT_APPROLE.md` — AppRole configuration
- `docs/VAULT_DYNAMIC_SECRETS.md` — Dynamic secrets setup

---

## Properties

✅ **Immutable:** All workflows + scripts versioned in Git  
✅ **Ephemeral:** Secrets generated on-demand, not stored locally  
✅ **Idempotent:** Same VAULT query → same secret output  
✅ **No-Ops:** All automated via workflows; no manual secret management  
✅ **Fully Automated:** Workflows trigger on schedule + events  
✅ **Hands-Off:** Zero operator intervention; VAULT handles rotation  

---

## Integration Points

### GitHub Actions Workflows
1. Authenticate to VAULT (AppRole)
2. Request dynamic secret
3. Use secret in workflow
4. Automatic lease cleanup on job completion

### External Systems
- **AWS:** IAM roles + KMS
- **HashiCorp VAULT:** Secret storage + dynamic generation
- **GCP:** Secret Manager (existing)
- **Internal:** Database, SSH runners, etc.

---

## Success Criteria

- ✅ AppRole authentication working
- ✅ Dynamic SSH credentials generated
- ✅ Secret rotation policies active
- ✅ Audit logs showing all access
- ✅ No long-lived secrets in GitHub
- ✅ All properties (immutable/ephemeral/idempotent/no-ops) verified

---

## Timeline

### Batch 3 Activation
- **When:** Post-Batch 2 merge (~30 min from now)
- **Duration:** ~20-30 min (CI + auto-merge)
- **Result:** VAULT framework live in all environments

### Next Phases
- **Phase 4:** Runtime upgrades & framework updates
- **Phase 5:** Final hardening & compliance scan

---

**Status:** Ready for auto-activation. All constraints (immutable, ephemeral, idempotent, no-ops, fully automated, hands-off, GSM, VAULT, KMS) will be satisfied.
