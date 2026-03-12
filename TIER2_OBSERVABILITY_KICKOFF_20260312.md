# TIER-2 PHASE 2: OBSERVABILITY WIRING & AWS MIGRATION
**Epic**: #2632  
**Date**: 2026-03-12T03:15:00Z UTC  
**Lead Engineer**: akushnir  
**Status**: ✅ READY TO KICK OFF

---

## PHASE OVERVIEW

This phase completes Tier-2 by implementing:
1. **Observability Wiring** — Slack/Teams notifications + uptime checks + synthetic monitoring
2. **AWS OIDC Migration** — Complete multi-cloud credential failover integration
3. **Phase 5 Scaling** — Performance optimization and capacity planning

---

## SCOPE BREAKDOWN

### Part 1: Notification Channels (Immediate - 30 mins)
**Objective**: Wire Slack/Teams webhooks and verify alert firing

**Tasks**:
1. ✅ Slack webhook secret provisioned (issue #2634 - GSM)
2. Create notification dispatcher script: `scripts/ops/notify-health-check.sh`
   - Parses health check results
   - Routes to Slack/Teams webhooks
   - Immutable audit logging (JSONL)
   - Idempotent (safe to re-run)
   
3. Wire to milestone organizer:
   - On success: Post status to slack (team alerts)
   - On failure: Post error + retry instructions to #ops-alerts
   - Log all notifications to audit trail

4. Test notification flow:
   - Simulate health check failure → verify Slack message
   - Verify retry logic and escalation
   - Check immutable audit trail (JSONL entries)

**Acceptance Criteria**:
- ✅ Slack webhook configured in GSM (`slack-webhook-prod`)
- ✅ Notification dispatcher script deployed to main
- ✅ Test notification received in #ops-alerts (Slack)
- ✅ Audit trail immutable and complete

**Estimated Effort**: 30 minutes

**Blocker (#2460)**: `slack-webhook` secret in GSM - already staged (resolved)

---

### Part 2: Uptime Checks & Synthetic Monitoring (45 mins)
**Objective**: Deploy Google Cloud Uptime Checks with synthetic health alerts

**Tasks**:
1. Create uptime check configuration:
   - Endpoints: Cloud Run services (milestone-organizer, backend, dashboard)
   - Protocol: HTTPS
   - Frequency: 1-minute checks
   - Timeout: 10 seconds
   - Locations: 5 regional checkers (US, EU, APAC)

2. Create alert policy:
   - Trigger: 2 consecutive check failures (>4 mins downtime)
   - Route to Slack via webhook dispatcher
   - Include: timestamp, endpoint, error details, retry link

3. Terraform automation:
   - File: `terraform/google-cloud-uptime-checks.tf`
   - Resources: `google_monitoring_uptime_check_config`, `google_monitoring_alert_policy`
   - Variables: endpoints, notification channels, alert thresholds
   - All idempotent (safe to apply multiple times)

4. Verification:
   - Apply Terraform: `terraform plan` → `apply`
   - Simulate endpoint failure (down service)
   - Verify alert fires within 2 minutes
   - Check Slack notification delivery
   - Verify audit trail (all actions logged)

**Acceptance Criteria**:
- ✅ Uptime checks deployed (Terraform)
- ✅ Alert policy created and active
- ✅ Simulated failure → alert fires
- ✅ Slack notification received within 2 minutes
- ✅ All changes committed to main with audit trail

**Estimated Effort**: 45 minutes

**Blocker (#2488)**: Org policy/compliance group for uptime checks - coordinate with ops

---

### Part 3: AWS OIDC Migration Completion (60 mins)
**Objective**: Document and stage AWS OIDC migration for Phase 5 execution

**Tasks**:
1. Multi-cloud credential architecture diagram:
   - Primary: AWS OIDC → STS (1h TTL, ephemeral)
   - Secondary: GSM → Vault JWT (if Vault available)
   - Tertiary: KMS encrypted local cache (12h TTL, offline capable)
   - Show failover chains and recovery paths

2. Create migration runbook: `docs/AWS_OIDC_MULTI_CLOUD_MIGRATION.md`
   - Current state: Direct GitHub OIDC → Terraform (primary)
   - Target state: AWS OIDC + fallback chain (GSM/Vault/KMS)
   - Migration steps (minimal downtime):
     * Deploy failover layer (GSM secrets, KMS key)
     * Test failover paths (manual then automated)
     * Update Terraform to use fallback chain
     * Monitor for 24 hours
     * Verify SLA compliance (< 5s failover)
   - Rollback procedure (if needed)

3. Stage deployment scripts:
   - `scripts/migrate/prepare-aws-oidc-fallover.sh` → idempotent prep
   - `scripts/migrate/activate-credential-failover.sh` → atomic activation
   - `scripts/migrate/verify-aws-oidc-migration.sh` → compliance check
   - All scripts logged to JSONL audit trail

4. Create test suite:
   - `scripts/tests/aws-oidc-failover-test.sh` (6 test cases)
   - Test cases:
     * AWS STS primary path (baseline)
     * GSM fallback (simulated AWS timeout)
     * Vault JWT fallback (both unavailable)
     * KMS cache fallback (all failed)
     * Recovery to primary (all restored)
     * Performance SLA (max 5s failover)

**Acceptance Criteria**:
- ✅ Multi-cloud architecture documented with diagrams
- ✅ Migration runbook with step-by-step instructions
- ✅ Deployment scripts (prepare, activate, verify)
- ✅ Test suite (6 test cases, all passing)
- ✅ Fallover SLA verified (< 5 seconds)
- ✅ All changes committed to main with audit trail

**Estimated Effort**: 60 minutes

---

### Part 4: Phase 5 Capacity Planning (30 mins)
**Objective**: Document Phase 5 scaling requirements and resource allocation

**Tasks**:
1. Review current resource utilization:
   - Cloud Run: CPU/memory/request rates
   - Cloud Scheduler: Job execution times
   - Cloud Logging: Log volume and retention
   - GCS/S3: Storage growth rate
   - Network: Egress costs

2. Create scaling plan: `docs/PHASE5_SCALING_PLAN.md`
   - Projected workload (next 30 days)
   - Bottleneck analysis (if any)
   - Scaling recommendations:
     * Cloud Run max instances
     * Memory limits (if applicable)
     * Log retention policy (cost optimization)
     * Storage cleanup schedule
   - Cost impact (estimated)

3. Stage Phase 5 work items:
   - Create sub-issues for each scaling task
   - Estimate effort and dependencies
   - Assign to owners
   - Label: phase5, planning, backlog

4. Document risk assessment:
   - What could fail at scale?
   - Mitigation strategies
   - Fallback plans
   - SLA targets

**Acceptance Criteria**:
- ✅ Current resource utilization captured
- ✅ Scaling plan documented (30-day projection)
- ✅ Bottleneck analysis complete
- ✅ Phase 5 sub-issues created and assigned
- ✅ Risk assessment documented

**Estimated Effort**: 30 minutes

---

## EXECUTION TIMELINE

```
2026-03-12T03:15Z → Kickoff #2632, begin Part 1 (notifications)
2026-03-12T03:45Z → Part 1 complete, begin Part 2 (uptime checks)
2026-03-12T04:30Z → Part 2 complete, begin Part 3 (AWS OIDC migration)
2026-03-12T05:30Z → Part 3 complete, begin Part 4 (Phase 5 planning)
2026-03-12T06:00Z → All parts complete, create sub-issues, assign owners
2026-03-12T06:05Z → Update #2632 with completion status
```

**Total Estimated Duration**: ~2.5 hours (all parts sequential, hands-off automation)

---

## GOVERNANCE COMPLIANCE

✅ **Immutable** — JSONL audit logs for all actions  
✅ **Ephemeral** — No persistent state (Terraform state in GCS)  
✅ **Idempotent** — All scripts safe to re-run  
✅ **No-Ops** — Fully automated after initial setup  
✅ **Hands-Off** — Uptime checks automated, alert dispatch automated  
✅ **Credentials** — AWS OIDC + GSM/Vault/KMS fallover chain  
✅ **Direct Deploy** — No GitHub Actions, main commits only  

---

## BLOCKERS IDENTIFIED

| Blocker | Issue | Status | Owner |
|---------|-------|--------|-------|
| Slack webhook secret (GSM) | #2460 | ✅ STAGED (ready) | ops |
| Org policy/compliance group | #2488 | ⏳ PENDING | compliance |
| Uptime check SA permissions | #2472 | ⏳ PENDING | sec |
| Cloud Audit group | #2469 | ⏳ PENDING | infra |

**Resolution**: All blockers will be coordinated with ops/sec teams in parallel.

---

## DELIVERABLES CHECKLIST

### Code
- [ ] `scripts/ops/notify-health-check.sh` (notification dispatcher)
- [ ] `scripts/migrate/prepare-aws-oidc-fallover.sh` (prep script)
- [ ] `scripts/migrate/activate-credential-failover.sh` (activation script)
- [ ] `scripts/migrate/verify-aws-oidc-migration.sh` (verification script)
- [ ] `scripts/tests/aws-oidc-failover-test.sh` (test suite, 6 cases)
- [ ] `terraform/google-cloud-uptime-checks.tf` (uptime checks + alerts)

### Documentation
- [ ] `docs/AWS_OIDC_MULTI_CLOUD_MIGRATION.md` (migration runbook)
- [ ] `docs/PHASE5_SCALING_PLAN.md` (capacity planning)
- [ ] Architecture diagram (multi-cloud credential failover)
- [ ] Risk assessment and mitigation strategies

### GitHub Issues
- [ ] #2632 updated with completion status comment
- [ ] 5+ Phase 5 sub-issues created and assigned
- [ ] Dependencies documented (which can run in parallel)

### Audit Trail
- [ ] All scripts logged to `logs/multi-cloud-audit/tier2-phase2-*.jsonl`
- [ ] Terraform apply/plan results archived
- [ ] Test execution logs captured
- [ ] Alert firing verification logged

---

## NEXT PHASE (Phase 5)

After #2632 is complete:
1. **Phase 5 Kickoff** — Scale workloads, add redundancy, optimize costs
2. **Observability Phase 2** — Dashboards, custom metrics, alerting
3. **Security Hardening** — Add RBAC, quotas, audit logging
4. **Capacity Planning** — Multi-region deployment, active-active setup

---

## NOTES

- All work follows governance requirements: immutable, ephemeral, idempotent, no-ops
- Lead engineer has authority for direct deployment (no PRs required)
- Automation-first approach: minimize manual intervention
- SLA targets: failover < 5 seconds, alert < 2 minutes, deployment < 1 hour
- Cost optimization: monitor resource growth, implement auto-cleanup

---

**Ready to Begin**: 2026-03-12T03:15Z UTC  
**Lead Engineer**: akushnir  
**Authorization**: Full autonomous execution approved

