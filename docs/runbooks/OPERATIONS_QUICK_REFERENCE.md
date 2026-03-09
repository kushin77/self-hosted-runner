# 🎯 OPERATIONS QUICK REFERENCE GUIDE
**For Production-Ready Self-Hosted Runner Infrastructure**

---

## ⚡ QUICK COMMANDS

### Day 0: Fresh Deployment

```bash
cd /home/akushnir/self-hosted-runner

# Execute complete production deployment (85 minutes, 0 manual steps)
bash orchestrate_production_deployment.sh

# Verify all 24 tests pass
bash test_deployment_0_to_100.sh
```

**Expected Outcome:**
- ✅ All 24 tests passing
- ✅ All services running (Vault, PostgreSQL, Redis, MinIO)
- ✅ Ephemeral credentials active
- ✅ Health monitoring daemon running
- ✅ Credential rotation scheduler active
- ✅ Production ready

---

### Health Status

```bash
# Quick health check (one-time run)
bash automation/health/health-check.sh once

# Continuous monitoring (runs indefinitely, 5-min intervals)
bash automation/health/health-check.sh

# Detailed health report
bash automation/health/health-check.sh report

# Expected: All items show ✅ HEALTHY
```

**Health Check Covers:**
- GSM connectivity
- Vault seal status & AppRole health
- KMS key status
- Service connectivity (Vault API, Postgres, Redis, MinIO)
- System resources (disk, memory)

---

### Credential Status

```bash
# Check credential layer health
bash automation/credentials/credential-management.sh health

# Fetch test credential (demonstrates multi-layer fallback)
bash automation/credentials/credential-management.sh test

# View audit log of credential operations
tail -50 logs/rotation/audit.log
```

**Credential Layers (Priority Order):**
1. GSM (Primary) - OIDC tokens, 1-use revocation
2. Vault (Secondary) - AppRole, 1-hour TTL
3. KMS (Tertiary) - Envelope encryption
4. GitHub (Fallback) - Ephemeral secrets, 24h

---

### Credential Rotation

```bash
# Automatic (runs on schedule, no manual action)
# - GSM: Daily 1:00 AM UTC
# - Vault: Weekly Sunday 00:00 UTC  
# - KMS: Quarterly 1st of month 00:00 UTC

# Manual rotation (if needed for maintenance)
bash automation/credentials/rotation-orchestrator.sh

# View rotation logs
tail -50 logs/rotation/rotation.log
tail -50 logs/rotation/audit.log
```

---

### Incident Response

```bash
# View recent incidents
tail -20 logs/health/health.log | grep INCIDENT

# Check incident details
grep "INCIDENT\|FAILURE\|ERROR" logs/health/health.log | tail -20

# Detailed incident investigation
cat logs/deployment-*/orchestrator.log | grep -i error
```

**Escalation Path:**
1. Auto-remediation (service restart, AppRole reset, etc.)
2. If still failing → Alert created
3. If persists > 15 min → PagerDuty notification
4. Manual investigation if auto-recovery fails

---

### System Reset (Emergency)

```bash
# Clean slate reset - rebuilds everything from scratch
bash nuke_and_deploy.sh

# Then run full deployment again
bash orchestrate_production_deployment.sh
```

**⚠️ WARNING**: Loses all data - use only for emergency reset

---

## 📋 PLAYBOOKS

### View Available Playbooks

```bash
bash automation/playbooks/deployment-playbooks.sh help
```

### Specific Playbooks

```bash
# 1. Initial Deployment (Day 0)
bash automation/playbooks/deployment-playbooks.sh 1

# 2. Credential Rotation (Recurring)
bash automation/playbooks/deployment-playbooks.sh 2

# 3. Health Monitoring & Recovery
bash automation/playbooks/deployment-playbooks.sh 3

# 4. Incident Response
bash automation/playbooks/deployment-playbooks.sh 4

# 5. Compliance Audit
bash automation/playbooks/deployment-playbooks.sh 5
```

---

## 🏛️ GOVERNANCE COMPLIANCE

### Check Governance Status

```bash
# Read governance policies
cat GOVERNANCE_POLICIES.md

# Quick compliance checklist
bash automation/playbooks/deployment-playbooks.sh 5  # Compliance Audit
```

### Verify 6 Core Principles

```bash
# 1. Immutability (all from git)
git log --oneline | head -3

# 2. Ephemerality (no long-lived creds)
bash automation/credentials/credential-management.sh health

# 3. Idempotency (repeatable deployments)
echo "Run this twice - results should be identical"
bash orchestrate_production_deployment.sh

# 4. Zero-Ops (no manual intervention)
ps aux | grep -E "health-check|rotation-orchestrator"

# 5. Hands-Off (fully automated)
tail -f logs/health/health.log

# 6. Full Automation (all operations scripted)
ls -la automation/
```

**All Green ✅ → Production Ready**

---

## 🔍 TROUBLESHOOTING

### Service Won't Start

```bash
# Check service-specific logs
docker-compose logs [SERVICE]

# Examples:
docker-compose logs vault
docker-compose logs postgres
docker-compose logs redis
docker-compose logs minio
```

### Credential Layer Offline

```bash
# Check which layer is down
bash automation/credentials/credential-management.sh health

# Diagnostic output shows:
# ✅ GSM: OK or ❌ GSM: UNREACHABLE
# ✅ Vault: OK or ❌ Vault: UNREACHABLE
# ✅ KMS: OK or ❌ KMS: UNREACHABLE
# ✅ GitHub: OK or ❌ GitHub: UNREACHABLE

# If primary layer down, system falls back to secondary or tertiary
# System remains operational with reduced security posture
# Escalate if multiple layers down
```

### Health Check Failing

```bash
# View detailed health status
bash automation/health/health-check.sh report

# Check if auto-remediation is running
tail -30 logs/health/health.log

# Manual remediation steps:
docker-compose restart [SERVICE]
# OR
bash automation/health/health-check.sh  # Starts monitoring daemon
```

### Rotation Still in Progress

```bash
# Check rotation status
ps aux | grep rotation-orchestrator

# View rotation logs
tail -50 logs/rotation/rotation.log

# Check if specific layer is being rotated
grep -i "gsm\|vault\|kms" logs/rotation/rotation.log | tail -20
```

### Tests Failing After Deploy

```bash
# Run full test suite
bash test_deployment_0_to_100.sh

# If failures, view test log
tail -50 logs/deployment-*/test.log

# Common causes:
# - Service not ready yet (wait 30-60 seconds)
# - Port already in use
# - Insufficient disk space
# - Credentials not loaded

# Remediate:
docker-compose ps  # Check all services
docker-compose logs vault | grep -i error
```

---

## 📊 MONITORING DASHBOARDS

### Real-Time Monitoring

```bash
# Terminal-based continuous monitoring
bash automation/health/health-check.sh

# Output format:
# [YYYY-MM-DD HH:MM:SS] Health Check Status:
# ✅ GSM: Healthy
# ✅ Vault: Healthy (AppRole: OK)
# ✅ KMS: Healthy (Rotation: Enabled)
# ✅ Service Connectivity: OK
# ✅ System Resources: Healthy (Disk: 85%, Memory: 65%)
# Overall Status: ✅ HEALTHY
```

### Health Report

```bash
# Detailed multi-page report
bash automation/health/health-check.sh report > /tmp/health-report.txt
less /tmp/health-report.txt

# Shows:
# - Each credential layer status
# - Service health metrics
# - Resource utilization
# - Incident history
# - Recommendation actions
```

### SLA Metrics

```bash
# Calculate uptime (requires logs)
grep "HEALTHY\|status: up" logs/health/health.log | wc -l
# Divide by total checks to get uptime percentage

# View incident frequency
grep "INCIDENT\|FAILURE" logs/health/health.log | wc -l
# Should be minimally (< 1 per week)
```

---

## 🔐 SECURITY OPERATIONS

### Access Control

```bash
# View recent access attempts (from logs)
grep "authentication\|access\|permission" logs/deployment-*/orchestrator.log

# Check who accessed credentials
grep "CREDENTIAL_ACCESS" logs/rotation/audit.log
```

### Credential Audit

```bash
# Monthly credential audit
grep "ROTATION\|VERIFY\|HEALTH" logs/rotation/audit.log | tail -100

# Check for unauthorized attempts
grep "FAILED\|DENIED\|ERROR" logs/rotation/audit.log
```

### Encryption Verification

```bash
# Verify all credentials encrypted
grep "encrypted\|encryption" logs/*.log

# Check KMS status
bash automation/credentials/credential-management.sh health | grep KMS

# Expected: KMS: Healthy (Key rotation: Enabled)
```

---

## 📈 PERFORMANCE TUNING

### Check Current Performance

```bash
# View resource usage
docker stats

# Check service response times
curl -w "@/tmp/curl-format.txt" -o /dev/null -s http://localhost:8200/v1/sys/health

# Database query performance
docker-compose exec postgres psql -U postgres -c "SELECT id, query_start FROM pg_stat_activity;"
```

### Optimize if Needed

```bash
# Increase health check interval (default 5 min)
# Edit: automation/health/health-check.sh
# Change: HEALTH_CHECK_INTERVAL=300  # seconds

# Tune Docker resources
# Edit: docker-compose.dev.yml
# Adjust: memory: 2g  # per service

# Restart with new settings
docker-compose restart
```

---

## 📝 COMMON OPERATIONAL TASKS

### Task: Enable/Disable Service

```bash
# Disable (stop but don't remove)
docker-compose stop [SERVICE]

# Enable (restart)
docker-compose start [SERVICE]

# Temporary disable (for maintenance)
docker-compose pause [SERVICE]

# Resume
docker-compose unpause [SERVICE]
```

### Task: View Service Logs

```bash
# Real-time logs
docker-compose logs -f [SERVICE]

# Last 50 lines
docker-compose logs --tail=50 [SERVICE]

# With timestamps
docker-compose logs --timestamps [SERVICE]

# Services: vault, postgres, redis, minio
```

### Task: Update Secrets

```bash
# Update GSM secret (will rotate automatically)
gcloud secrets versions add terraform-aws-prod --data-file=-

# Verify update
bash automation/credentials/credential-management.sh health

# Services using it will auto-refresh on next health check
```

### Task: Backup Data

```bash
# Backup is automatic (running in background)
# Backup location: docker-compose.dev.yml volumes section

# Manual backup
docker-compose exec postgres pg_dump -U postgres > /tmp/backup.sql

# Verify backup
ls -lh /tmp/backup.sql
```

### Task: Restore from Backup

```bash
# Reset system
bash nuke_and_deploy.sh

# Deploy fresh
bash orchestrate_production_deployment.sh

# Restore data (if available)
docker-compose exec postgres psql -U postgres < /tmp/backup.sql
```

---

## ⏰ MAINTENANCE SCHEDULE

### Daily (Automated)
- [x] Health checks (5-min intervals)
- [x] GSM credential rotation (1:00 AM UTC)
- [x] Monitoring & alerting
- [x] Audit log rotation

### Weekly (Automated)
- [x] Vault AppRole rotation (Sunday 00:00 UTC)
- [x] Security scans
- [x] Performance reports

### Monthly (Manual Review)
- [ ] Compliance audit (review automated audit)
- [ ] Access control review
- [ ] Incident review & RCA
- [ ] Documentation update

### Quarterly (Manual)
- [ ] KMS key rotation enablement (automated)
- [ ] Disaster recovery test
- [ ] Security posture assessment
- [ ] Governance policy review

### Annually
- [ ] Third-party penetration test
- [ ] Comprehensive security audit
- [ ] Capacity planning review
- [ ] Major version upgrades

---

## 🚨 EMERGENCY CONTACTS

```
For Production Issues:
- PagerDuty: [Auto-escalated by system]
- Slack Channel: #production-alerts
- Email: devops-team@example.com

For Security Incidents:
- Security Team: security@example.com
- ISMS: [incident-severity-module]
```

---

## 📚 ADDITIONAL RESOURCES

```
Governance Policies:      GOVERNANCE_POLICIES.md
Deployment Guide:         PRODUCTION_DEPLOYMENT_PACKAGE.md
Fresh Deploy Guide:       FRESH_DEPLOY_GUIDE.md
Playbooks:               automation/playbooks/deployment-playbooks.sh
Execution Report:        EXECUTION_ACTION_REPORT.md
```

---

## ✅ CHECKLIST: Am I Ready?

Before attempting production operations:

- [ ] Read GOVERNANCE_POLICIES.md
- [ ] Reviewed OPERATIONS_QUICK_REFERENCE.md (this file)
- [ ] Day 0 deployment successful
- [ ] All 24 tests passing
- [ ] Health monitoring running
- [ ] Credential health verified
- [ ] Playbooks understood
- [ ] Escalation path clear
- [ ] Backup verified
- [ ] Team trained

**If ALL checked ✅ → READY FOR PRODUCTION**

---

**Last Updated**: March 8, 2026  
**Version**: 1.0  
**Status**: ✅ PRODUCTION READY

For questions or updates, create an issue: github.com/[org]/self-hosted-runner/issues
