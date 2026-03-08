# 🚀 PRODUCTION OPERATIONS RUNBOOK

**Status:** ✅ **FULLY OPERATIONAL**  
**Last Updated:** 2026-03-08  
**Version:** 2.0  

---

## Quick Start for Operations Team

### Daily Operations (Automated - No Action Needed)

| Task | When | What Happens | Your Role |
|------|------|--------------|-----------|
| Credential Rotation | 02:00 UTC daily | All credentials auto-rotated | Monitor dashboard |
| Compliance Report | 08:00 UTC daily | Daily audit generated | Review & archive |
| Health Check | Every hour | System health verified | Alert if fails |
| SLA Tracking | Continuous | 99.9% auth, 100% rotation tracked | Check dashboard weekly |

### What You Don't Need To Do

❌ **Don't DeFiguree:**
- Manually rotate credentials
- Create new secrets
- Update GitHub Actions secrets
- Manage Vault/GSM/KMS directly
- Monitor individual workflows
- Maintain audit logs manually

✅ **All of that is automated!**

---

## Monitoring & Dashboards

### View Live Metrics

```bash
# Authentication SLA Status
bash .monitoring-hub/dashboards/sla-dashboard.sh

# System Health Status  
bash .monitoring-hub/dashboards/health-dashboard.sh

# Threat Detection Status
cat .security-enhancements/threat-detection/threats-$(date +%Y%m%d).jsonl
```

### Understanding SLA Metrics

**Auth SLA (Target: 99.9%)**  
This tracks successful credential authentications. Track it weekly to ensure healthy auth operations.

**Rotation SLA (Target: 100%)**  
This tracks successful credential rotations. 100% means all credentials rotated without errors.

**Thresholds:**
- Green: 99.9%+ (Auth), 99%+ (Rotation)
- Yellow: 99% (Auth), 95% (Rotation)
- Red: <99% (Auth), <95% (Rotation)

---

## Emergency Procedures

### Scenario 1: Exposed Credentials Detected

**Symptoms:**  
- Threat detection alert
- Credential scan shows active exposure
- Audit log shows unauthorized access attempt

**Actions (< 5 minutes):**

```bash
# 1. Immediate revocation
bash scripts/operations/emergency-test-suite.sh --execute revoke-exposed

# 2. Verify services still healthy
curl https://your-service/health

# 3. Document incident
# Create incident log in .security-enhancements/incidents/
```

**Follow-up (within 24 hours):**
- Review what credential was exposed
- Check if attacker accessed any systems
- Rotate any related credentials manually
- File incident report for compliance

---

### Scenario 2: Workflow Failed (Non-Auto-Recovery)

**Symptoms:**
- Workflow shows "failed" status in GitHub
- Escalation alert triggered
- Services may be degraded

**Actions (< 15 minutes):**

```bash
# 1. View workflow logs
gh run view <RUN_ID> --json log

# 2. Check what failed
# Common failures: network, permission, timeout

# 3. Execute recovery
bash scripts/operations/workflow-recovery.sh <WORKFLOW_NAME>

# 4. Monitor for success
gh run list --workflow <WORKFLOW_NAME>.yml

# 5. Escalate if still failing
# Contact: On-call primary → Secondary → Infrastructure lead
```

---

### Scenario 3: SLA Violation

**Symptoms:**
- SLA dashboard shows red
- Alert notification sent
- Monitoring system flags violation

**Actions (< 30 minutes):**

```bash
# 1. Identify which SLA failed
bash .monitoring-hub/dashboards/sla-dashboard.sh

# 2. Root cause analysis
# Check logs for errors:
jq '.status | select(.status != "success")' .operations-audit/*.jsonl | head -20

# 3. Determine action
if [ "$TYPE" == "auth_sla" ]; then
  # Investigate credential provider access (GSM/Vault/KMS)
  # Check network connectivity
  # Verify credential backends are operational
elif [ "$TYPE" == "rotation_sla" ]; then
  # Check rotation workflow logs
  # Verify credentials are still valid
  # Investigate permission errors
fi

# 4. Execute fix or escalate
```

---

## Escalation Contacts

**Level 1 - Immediate (No delay)**
- On-Call Primary: [Name/Phone]
- On-Call Slack: #oncall

**Level 2 - 15 minutes**
- On-Call Secondary: [Name/Phone]
- Engineering Lead: [Name/Phone]

**Level 3 - 30 minutes**
- Infrastructure Lead: [Name/Phone]
- Security Lead: [Name/Phone]

**Level 4 - 1 hour**
- CTO/Director: [Name/Phone]
- War Room: [Conference Room/Zoom]

---

## Common Issues & Solutions

### Issue 1: "Cannot retrieve credentials"

**Symptoms:**
- Workflow shows "credential retrieval failed"
- Service logs show "authentication failure"

**Solution:**
```bash
# Check credential backend status
[ -f ".gsm-config" ] && echo "✓ GSM available" || echo "✗ GSM not initialized"
[ -f ".vault-config" ] && echo "✓ Vault available" || echo "✗ Vault not initialized"
[ -f ".kms-config" ] && echo "✓ KMS available" || echo "✗ KMS not initialized"

# Verify network connectivity
ping cloud.google.com && echo "✓ GCP reachable"
ping vault.example.com && echo "✓ Vault reachable"
aws sts get-caller-identity && echo "✓ AWS reachable"
```

### Issue 2: "Rotation failed with permission error"

**Symptoms:**
- Rotation workflow fails
- Error message mentions "denied" or "forbidden"

**Solution:**
```bash
# Check IAM roles are correct
gcloud projects get-iam-policy $PROJECT_ID
aws iam get-role --role-name github-actions-role

# Verify service account permissions
# May need to re-run Phase 2 (OIDC setup) if roles were modified
```

### Issue 3: "Audit trail shows suspicious activity"

**Symptoms:**
- Threat detection alert triggered
- Unusual pattern in audit logs

**Solution:**
```bash
# Investigate threat log
cat .security-enhancements/threat-detection/threats-$(date +%Y%m%d).jsonl

# Check for brute force
grep '"status":"failed"' .deployment-audit/*.jsonl | wc -l

# Check for privilege escalation
grep '"permission":"admin"' .operations-audit/*.jsonl | wc -l

# If confirmed threat, escalate immediately
```

---

## Weekly Tasks (Review Only - No Action)

**Every Monday:**
```bash
# Review SLA for past week
bash .monitoring-hub/dashboards/sla-dashboard.sh

# Check for any incidents
grep "CRITICAL\|HIGH" .security-enhancements/threat-detection/threats-*.jsonl || echo "No issues"

# Archive compliance report
mv .operations-audit/compliance-report-*.json compliance-archive/
```

**Monthly:**
```bash
# Verify audit trail integrity
bash .security-enhancements/audit-chain-of-custody.sh --verify

# Review incident reports
ls security-enhancements/incidents/

# Update escalation contacts
# Ensure phone numbers and emails are current
```

---

## Documentation & References

| Document | Purpose | Audience |
|----------|---------|----------|
| PRODUCTION_LIVE_SUMMARY.md | System overview | All |
| GO_LIVE_CHECKLIST.md | Pre-production verification | Leadership |
| EMERGENCY_ROLLBACK_PLAN.md | Disaster recovery | Operations |
| GIT_GOVERNANCE_STANDARDS.md | Code standards | Engineers |

---

## Support & Questions

**For Questions:**
1. Check this runbook first
2. Search .operational-readiness documentation
3. Check GitHub issue #1972 and related issues
4. Contact on-call primary

**For Bug Reports:**
```bash
gh issue create \
  --title "Production Issue: [Brief Description]" \
  --body "Describe issue, symptoms, and steps to reproduce" \
  --assignee akushnir \
  --label security,production
```

---

## Key Metrics to Track

**Monthly Review:**
- Auth SLA: Target 99.9%
- Rotation SLA: Target 100%
- Mean Time To Resolution (MTTR): Target < 15 minutes
- Incident Count: Target 0 (security), < 2 (other)

**Quarterly Review:**
- Audit trail completeness: 100%
- Threat detection accuracy: > 98%
- Team training completion: 100%
- DR (Disaster Recovery) test: 1/quarter required

---

## Going Forward

**Next 30 Days:**
- [ ] Confirm all monitoring dashboards accessible to team
- [ ] Run monthly disaster recovery test
- [ ] Update escalation contacts
- [ ] Conduct security training refresh

**Next 90 Days:**
- [ ] Review and optimize alert thresholds
- [ ] Assess credential provider performance (GSM/Vault/KMS)
- [ ] Plan credential rotation strategy refinements
- [ ] Update runbooks based on lessons learned

**Next Year:**
- [ ] Complete full security audit
- [ ] Migrate to next-generation secrets management (if needed)
- [ ] Document all operational improvements
- [ ] Capture lessons learned for enterprise standards

---

**Status: ✅ System is production-ready and fully automated.**  
**No manual credential management needed.**  
**All critical operations secured and monitored 24/7.**

For questions email: ops-team@company.com  
For emergencies call: [Escalation number]
