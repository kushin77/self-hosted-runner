# 📋 GOVERNANCE POLICIES & COMPLIANCE FRAMEWORK
**Production-Ready Infrastructure Governance (FAANG Standards)**

---

## 1. 🎯 CORE PRINCIPLES

### 1.1 Immutability
**Definition**: All infrastructure components are code-versioned and immutable.

**Implementation**:
- ✅ All configuration in git
- ✅ No manual changes to running systems
- ✅ Infrastructure as Code (Terraform)
- ✅ Complete audit trail in git history
- ✅ Reproducible from git commit SHA

**Verification**:
```bash
# All infrastructure must be deployable from git
git clone <repo> && cd self-hosted-runner && bash orchestrate_production_deployment.sh
# Result: Identical infrastructure deployed
```

**Governance Rule**: 
- **ENFORCE**: Pre-commit hooks block manual service changes
- **ENFORCE**: All changes require PR with 2 approvals
- **ENFORCE**: Branch protection on main/master
- **ENFORCE**: Commit signing required

---

### 1.2 Ephemerality
**Definition**: No long-lived credentials; all tokens auto-revoke.

**Implementation**:
- ✅ GSM OIDC tokens (revoked after 1 use)
- ✅ Vault AppRole tokens (1-hour TTL)
- ✅ KMS temporary envelope keys (per-operation)
- ✅ GitHub ephemeral secrets (24h cleanup)
- ✅ No persistent credentials stored locally

**Token Specifications**:
| Layer | Type | TTL | Revocation | Fallback |
|-------|------|-----|-----------|----------|
| GSM | OIDC | 1 use | Immediate | Vault |
| Vault | AppRole | 1 hour | Auto | KMS |
| KMS | Envelope | Per-op | Immediate | GitHub |
| GitHub | Secret | 24 hours | Auto-cleanup | Manual |

**Governance Rule**:
- **BLOCK**: Any credential TTL > 24 hours
- **ENFORCE**: Rotation schedule compliance (daily/weekly/quarterly)
- **ALERT**: Long-lived token detection
- **REMEDIATE**: Auto-revoke on detection

---

### 1.3 Idempotency
**Definition**: Operations always produce same result regardless of run count.

**Implementation**:
- ✅ All scripts check before applying changes
- ✅ No side effects on repeated execution
- ✅ State reconciliation (drift detection)
- ✅ Safe to run in cronjob/scheduler

**Script Pattern**:
```bash
# Check current state
current_state=$(get_current_state)

# Only change if needed
if [[ "$current_state" != "$desired_state" ]]; then
    apply_change
    verify_change
fi
```

**Governance Rule**:
- **ENFORCE**: All automation scripts must be idempotent
- **TEST**: Every script validated for 3x execution test
- **FAIL**: Non-idempotent scripts blocked from merge

---

### 1.4 Zero Operators (No-Ops)
**Definition**: Zero manual operator intervention required.

**Implementation**:
- ✅ Fully automated deployment (85 minutes, zero manual steps)
- ✅ Health monitoring (5-minute checks)
- ✅ Self-healing (automatic remediation)
- ✅ Incident response (automatic escalation)
- ✅ All operations scheduled or event-triggered

**Automation Coverage**:
- Deployment: ✅ 0% manual
- Health checks: ✅ 100% automatic
- Incident response: ✅ 95% automatic (5% escalation)
- Credential rotation: ✅ 100% automatic
- Backup/restore: ✅ 100% automatic
- Monitoring: ✅ 100% automatic

**Governance Rule**:
- **ENFORCE**: Manual approval only needed for production access
- **BLOCK**: Non-automated operations
- **MONITOR**: Any manual action triggers review

---

### 1.5 Hands-Off Operations
**Definition**: System requires no human operator attention.

**Implementation**:
- ✅ Cron-based automation (no human intervention)
- ✅ Event-triggered workflows (GitHub Actions)
- ✅ Self-healing automation (health-check daemon)
- ✅ Incident escalation (PagerDuty/Slack only)
- ✅ Complete audit trail (no lost actions)

**Hands-Off Checklist**:
- [x] Credential rotation: Scheduled (no human action)
- [x] Health monitoring: 5-minute daemon (no human action)
- [x] Security scans: Daily cron (no human action)
- [x] Backups: Hourly + weekly scheduled (no human action)
- [x] Alerts: Auto-escalation to PagerDuty (human reviews)

**Governance Rule**:
- **ENFORCE**: No standing oncall; escalation only via automation
- **MONITOR**: All automation logs for failures
- **REVIEW**: Weekly automation effectiveness review

---

### 1.6 Full Automation
**Definition**: Every operation is code-driven and scriptable.

**Implementation**:
- ✅ Multi-layer credential management (4 layers)
- ✅ Continuous health monitoring (5-min intervals)
- ✅ Automatic self-healing (3-tier remediation)
- ✅ Scheduled rotation (daily/weekly/quarterly)
- ✅ Complete audit logging (all operations)
- ✅ Zero manual configuration steps

**Automation Inventory**:
```
orchestrate_production_deployment.sh     [6 phases, 85 min, 0 manual]
├─ nuke_and_deploy.sh                   [Fresh deploy, fully automated]
├─ automation/credentials/
│  ├─ credential-management.sh          [GSM/Vault/KMS lifecycle]
│  ├─ rotation-orchestrator.sh          [Daily/weekly/quarterly rotation]
│  └─ multi-layer-fallback.sh           [4-layer credential resolution]
├─ automation/health/
│  ├─ health-check.sh                   [5-min checks, auto-remediation]
│  └─ incident-escalation.sh            [PagerDuty/Slack integration]
└─ test_deployment_0_to_100.sh         [24 comprehensive tests]
```

**Governance Rule**:
- **ENFORCE**: All operations must have code/script
- **REVIEW**: No manual CLI commands in production
- **AUDIT**: All scripts version-controlled in git

---

## 2. 🔐 SECURITY FRAMEWORK

### 2.1 Credential Management

**Multi-Layer Strategy**:
1. **Primary**: GCP Secret Manager (OIDC integration)
2. **Secondary**: HashiCorp Vault (AppRole + dynamic secrets)
3. **Tertiary**: AWS KMS (envelope encryption)
4. **Fallback**: GitHub Secrets (ephemeral only)

**Credential Rotation Schedule**:
- GSM: Daily (1:00 AM UTC)
- Vault: Weekly (Sunday 00:00 UTC)
- KMS: Quarterly (1st of month 00:00 UTC)
- GitHub: Auto-cleanup (24-hour lifecycle)

**Access Control**:
```
Credential Layer          | Access Method | Authentication | TTL
--------------------------|---------------|-----------------|----------
GSM (Primary)            | OIDC Token    | Workload Identity| 1 use
Vault (Secondary)        | AppRole       | Secret ID Rotation| 1 hour
KMS (Tertiary)          | IAM Role      | Federated Auth  | Per-op
GitHub (Fallback)        | API Token     | Ephemeral User  | 24 hours
```

**Governance Rules**:
- ✅ No plaintext credentials in code
- ✅ No credentials in Docker images
- ✅ No hardcoded secrets in scripts
- ✅ All credential access logged
- ✅ Suspicious access triggers alert
- ✅ Credential sharing strictly prohibited

---

### 2.2 Encryption

**At Rest**:
- Database secrets: AWS KMS envelope encryption
- Service credentials: GSM versioning + encryption
- Configuration files: Git-crypt (future)
- Backup data: KMS default key encryption

**In Transit**:
- All APIs: HTTPS with TLS 1.3+
- Docker registry: HTTPS with certificate verification
- Git operations: SSH with Ed25519 keys
- Service mesh: Mutual TLS between services

**Key Management**:
- KMS keys: Automatic quarterly rotation
- SSH keys: Annual rotation + Ed25519 standard
- TLS certs: Let's Encrypt with auto-renewal
- Backup keys: Stored separately in KMS

**Governance Rules**:
- ✅ All credentials encrypted at rest
- ✅ TLS 1.2 minimum (1.3 preferred)
- ✅ Key rotation on schedule
- ✅ Zero unencrypted backups
- ✅ Encryption verified by compliance audit

---

### 2.3 Access Control

**RBAC Model**:
```
Role                  | Permissions                | Credential TTL
---------------------|----------------------------|----------------
Developer            | Read secrets (GSM)         | 1 hour
DevOps Engineer      | Rotate credentials         | 4 hours
Platform Admin       | Full access + approval     | 8 hours
Emergency Break-glass| Full access with audit log | 1 hour
```

**Approval Requirements**:
- Production secret read: 1 approver (lead)
- Credential rotation: 1 approver (devops)
- Infrastructure change: 2 approvers (tech leads)
- Policy change: 3 approvers (security + leads + exec)

**Governance Rules**:
- ✅ Least privilege by default
- ✅ Zero standing access (time-limited)
- ✅ All access requires approval
- ✅ Access logs reviewed weekly
- ✅ Suspicious activity auto-blocked

---

## 3. 📊 OPERATIONAL STANDARDS

### 3.1 Deployment Standards

**Pre-Deployment Checklist**:
- ✅ All tests passing (24/24)
- ✅ Code reviewed + approved (2 approvals)
- ✅ Security scan clean (no vulns)
- ✅ Performance baseline validated
- ✅ Rollback plan documented

**Deployment Procedure**:
- ✅ Use orchestrate_production_deployment.sh ONLY
- ✅ No manual changes to production
- ✅ All changes logged to git
- ✅ Health monitoring active during deploy
- ✅ Automatic rollback on failure

**Post-Deployment Verification**:
```bash
# Automatic verification runs
bash test_deployment_0_to_100.sh
# 24 tests must pass, including:
# - Service health (4 tests)
# - Connectivity (5 tests)
# - Data persistence (3 tests)
# - Security (2 tests)
```

**Governance Rules**:
- ✅ Deployments only via orchestration script
- ✅ No hotfixes without PR + approval
- ✅ Rollback automatic on test failure
- ✅ Deployment window: Anytime (fully automated)

---

### 3.2 Health & Monitoring Standards

**Health Check Intervals**:
- Credential layers: 5 minutes
- Services: 5 minutes (integrated)
- System metrics: 1 minute
- Application health: 10 minutes

**SLA Targets**:
- Service availability: 99.9% uptime
- Mean Time to Detection: < 5 minutes
- Mean Time to Respond: < 5 minutes (automatic)
- Mean Time to Recovery: < 5 minutes (automatic)

**Escalation Path**:
1. Detection (5 min) → Auto-recovery attempt
2. Recovery failure → Incident creation
3. Incident persistence → PagerDuty alert
4. Manual intervention needed → On-call escalation

**Governance Rules**:
- ✅ Health monitoring runs 24/7
- ✅ All alerts logged automatically
- ✅ No ignored alerts (action required)
- ✅ Recovery success rate tracked
- ✅ Incident reviews weekly

---

### 3.3 Incident Response Standards

**Incident Severity Levels**:
```
Level | Condition | Auto-Recovery | Manual Action | Escalation
------|-----------|---------------|---------------|------------------
P4    | Health warning | Auto-retry | Review logs | None
P3    | Service slow | Auto-recovery | Monitor | None (unless continues)
P2    | Service unavailable | Auto-recovery + restart | Investigate | PagerDuty if P2 > 5 min
P1    | Data loss risk | Immediate manual + auto | Full response | PagerDuty immediately
```

**Auto-Recovery Actions**:
1. Service health check (3 retries)
2. Docker container restart
3. Vault AppRole reinitialization
4. KMS key re-enable if needed
5. Full system restart (last resort)

**Manual Escalation Criteria**:
- Auto-recovery attempts failed 3x
- Incident persists > 15 minutes
- Service unavailability confirmed
- Data loss risk detected

**Governance Rules**:
- ✅ All incidents logged automatically
- ✅ Auto-recovery priority (minimize manual ops)
- ✅ Manual action only if auto-recovery fails
- ✅ Post-incident review within 24 hours
- ✅ RCA required for all P1/P2 incidents

---

## 4. 📋 COMPLIANCE & AUDIT

### 4.1 Audit Logging

**Comprehensive Audit Trail**:
```
Operation Type        | Logged Info              | Retention
----------------------|--------------------------|----------
Credential Access     | Who, when, what, result  | 1 year
Credential Rotation   | Layer, before, after     | 1 year
Configuration Change  | Git commit SHA           | Indefinite (git)
Security Event        | Type, severity, action   | 1 year
Authentication Failure| User, timestamp, reason  | 90 days
Incident Escalation   | Trigger, actions taken   | 1 year
```

**Log Locations**:
- Deployment: `logs/deployment-*/orchestrator.log`
- Health: `logs/health/health.log`
- Rotation: `logs/rotation/rotation.log` + `audit.log`
- Git: `git log --all` (complete history)
- Docker: `docker-compose logs [service]`

**Governance Rules**:
- ✅ All operations logged automatically
- ✅ Logs cannot be deleted (git + audit trail)
- ✅ Suspicious activity alerts within 1 min
- ✅ Log review required for compliance audit
- ✅ Incident correlation via logs

---

### 4.2 Compliance Audit

**Monthly Audit Checklist**:
- [ ] Credential audit: All rotations on schedule
- [ ] Access audit: Review all access logs
- [ ] Security audit: Vulnerability scan clean
- [ ] Availability audit: 99.9% target met
- [ ] Incident audit: Post-mortems completed
- [ ] Governance audit: Policy compliance verified

**Quarterly Compliance Review**:
- [ ] FAANG governance principles verified
- [ ] Immutability confirmed (all from git)
- [ ] Ephemerality confirmed (no long-lived creds)
- [ ] Idempotency tested (3x execution test)
- [ ] Zero-ops verified (automation working)
- [ ] Hands-off validated (no manual interventions)
- [ ] Documentation audit (current & complete)
- [ ] Security posture assessed

**Annual Security Audit**:
- [ ] Third-party penetration test
- [ ] Credential rotation effectiveness
- [ ] Access control review
- [ ] Encryption validation
- [ ] Incident response drill
- [ ] Disaster recovery test

**Governance Rules**:
- ✅ Monthly audit mandatory
- ✅ Non-compliance requires immediate action
- ✅ Quarterly governance review required
- ✅ Annual security audit scheduled
- ✅ Audit reports retained 3 years

---

## 5. 🔧 POLICY ENFORCEMENT

### 5.1 Automated Enforcement

**Pre-Commit Hooks**:
```bash
✅ Secret detection (no credentials in code)
✅ Credential rotation verification
✅ Idempotency check (scripts tested)
✅ Syntax validation (shell, terraform)
✅ Security scanning (semgrep, etc.)
```

**CI/CD Validation**:
```bash
✅ All tests passing (24/24)
✅ Code review passed (2+ approvals)
✅ Security scan clean (sarif output)
✅ No policy violations
✅ Deployment requirements met
```

**Branch Protection**:
```bash
✅ Require Draft issue reviews (minimum 2)
✅ Require status checks to pass
✅ Require branches to be up to date
✅ Dismiss stale PR approvals
✅ Require commit signatures
✅ Block force pushes
✅ Block deletions
```

**Policy Violations**:
- Hardcoded secret → Commit rejected + manual cleanup required
- Non-idempotent script → Merge blocked
- Timeout credential → Auto-revoked + incident created
- Manual prod change → Auto-rollback + review required
- Failed health check → Deployment blocked

---

### 5.2 Manual Review Process

**For Policy Exceptions**:
1. Submit exception request (GitHub issue)
2. Justify business need
3. Require 3 approvals (security + lead + exec)
4. Set automatic expiration date
5. Audit exception usage closely
6. Review quarterly

**Escalation Path**:
- Level 1: Team lead review (1 approval)
- Level 2: Security team review (2 approvals)
- Level 3: Executive approval (1 approval)
- Level 4: Board-level review (if needed)

**Governance Rules**:
- ✅ No exceptions by default
- ✅ All exceptions logged
- ✅ Exceptions expire automatically
- ✅ Escalation path transparent
- ✅ Exception metrics tracked

---

## 6. 📊 METRICS & REPORTING

### 6.1 SLA Metrics

**Service Availability**:
- Target: 99.9% uptime
- Calculation: (Total Time - Downtime) / Total Time
- Review: Weekly

**Mean Time Metrics**:
- MTTD (Detection): < 5 minutes
- MTTR (Response): < 5 minutes
- MTBF (Between failures): > 30 days

**Incident Metrics**:
- Total incidents: Tracked
- Auto-recovered: Target 95%
- Manual escalations: < 5%
- Business impact: Tracked

---

### 6.2 Reporting

**Daily Report** (Automated):
```
✅ 24/24 tests passing
✅ All services healthy
✅ Credentials rotated on schedule
✅ 0 security alerts
✅ 0 incidents
✅ 99.99% availability last 24h
```

**Weekly Report** (Manual review):
- Incident summary
- Performance metrics
- Security posture
- Recommendations

**Monthly Report** (Compliance):
- Audit findings
- Policy compliance
- Exception review
- Trend analysis

---

## 7. 📚 EXCEPTIONS & REVISIONS

### 7.1 Approved Exceptions

**None currently** - All policies fully implemented and enforced.

To request exception:
1. Create GitHub issue titled: "POLICY EXCEPTION: [Policy Name]"
2. Provide business justification
3. Specify duration (expires after date)
4. Request approvals (3 required)

---

### 7.2 Policy Revision Cycle

- **Reviewed**: Monthly with operations team
- **Updated**: Quarterly based on learnings
- **Major Changes**: Quarters with governance review
- **Industry Updates**: Annual security audit incorporates latest standards

---

## ✅ GOVERNANCE AUDIT CHECKLIST

Use this to verify governance compliance:

```bash
# 1. Immutability
git log --oneline | head -1  # Latest commit for deployments

# 2. Ephemerality
bash automation/credentials/credential-management.sh health

# 3. Idempotency
bash orchestrate_production_deployment.sh  # Run twice - should be identical

# 4. Zero-Ops
ps aux | grep -E "health-check|rotation-orchestrator"  # Daemons running

# 5. Hands-Off
tail -f logs/health/health.log  # Monitoring continuous

# 6. Full Automation
bash automation/playbooks/deployment-playbooks.sh 5  # Verify all automated
```

**All Checks Pass ✅ → Governance Compliant**

---

**Last Updated**: March 8, 2026
**Governance Officer**: DevOps Lead
**Approval Status**: ✅ APPROVED & ENFORCED
