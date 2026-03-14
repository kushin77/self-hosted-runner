# Workload Identity Federation - Completion & Test Plan

## Status: Infrastructure Ready ✅

### Verified Configuration
- **Project:** nexusshield-prod (151423364222)
- **WI Pool:** `runner-pool-20260311` ✅ (verified to exist)
- **OIDC Provider:** `runner-provider-20260311` (GitHub Actions)
- **Service Account:** `nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com`
- **IAM Binding:** `roles/iam.workloadIdentityUser` granted

### Token Exchange Scripts Ready
- **Exchange Script:** `scripts/auth/exchange-wi-token.sh`
  - Implements STS token exchange (RFC 8693)
  - Converts OIDC JWT → Google access token → Service account token
  - Usage: `SUBJECT_TOKEN="..." PROJECT_NUMBER=151423364222 WI_POOL=runner-pool-20260311 WI_PROVIDER=runner-provider-20260311 SA_EMAIL=... ./scripts/auth/exchange-wi-token.sh --print-token`

- **gcloud Wrapper:** `scripts/auth/wrap-gcloud-with-wi.sh`
  - Wraps gcloud commands with ephemeral WI tokens
  - Usage: `SUBJECT_TOKEN="..." ... ./wrap-gcloud-with-wi.sh gcloud iam service-accounts list`

## Next Steps to Complete Migration

### 1. Generate Test Token ⏳
**Option A: GitHub Actions (Production)**
- Run in GitHub Actions workflow: `SUBJECT_TOKEN=${{ secrets.GITHUB_TOKEN }}`
- Provides real GitHub OIDC token
- Best for integration testing

**Option B: Local Testing**
- Use `gcloud auth application-default print-access-token` output
- Limited but useful for basic validation
- Test exchange flow without GitHub context

### 2. Run Token Exchange Test
```bash
export PROJECT_NUMBER=151423364222
export WI_POOL=runner-pool-20260311
export WI_PROVIDER=runner-provider-20260311
export SA_EMAIL=nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com
export SUBJECT_TOKEN="<github-oidc-token>"  # From GitHub Actions or test

./scripts/auth/exchange-wi-token.sh --print-token
```

### 3. Verify gcloud Integration
```bash
./scripts/auth/wrap-gcloud-with-wi.sh gcloud iam service-accounts list
```
Should return list of service accounts using ephemeral token (no JSON key file).

### 4. Revoke Fallback Key
Once token exchange verified:
```bash
KEY_ID="a3b789c7..."  # From GSM as nxs-automation-sa-key
gcloud iam service-accounts keys delete $KEY_ID \
  --iam-account=$SA_EMAIL \
  --project=nexusshield-prod --quiet
```

### 5. Audit & Documentation
- Append final test results to `artifacts/audit/workload-identity-20260311.jsonl`
- Update `docs/WORKLOAD_IDENTITY_MIGRATION_RUNBOOK.md` with test results
- Close issue #2557 with migration complete status

## Monitoring & Metrics

**Audit Trail:** `artifacts/audit/workload-identity-20260311.jsonl` (append-only)

**Metrics to Validate:**
- Token exchange latency (STS → IAMCredentials)
- Successful token generation count
- Failed exchange attempts (if any)
- Service account impersonation log entries

## Risk Mitigation

- ✅ Old keys backed up in GSM
- ✅ Test in non-prod first (can revert by re-creating keys)
- ✅ Gradual rollout: test → enable → verify → revoke
- ✅ 24-hour monitoring before key revocation

## Completion Criteria

- [ ] Token exchange test succeeds
- [ ] gcloud wrapper works with WI token
- [ ] Fallback key revoked
- [ ] Audit trail finalized
- [ ] Documentation updated
- [ ] Issue #2557 closed
- [ ] Team notified of keyless auth readiness

---
Generated: 2026-03-11
Next Review: After token exchange test
