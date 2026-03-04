# ✅ PRE-DEPLOYMENT CHECKLIST - PHASE P0 & P1

**Date**: March 4, 2026  
**Status**: Production Deployment Ready  
**Use This**: Before deploying Phase P0 to staging or production

---

## 📋 PRE-DEPLOYMENT VALIDATION (BEFORE EVERY DEPLOYMENT)

### A. CODE VALIDATION ✓

- [ ] **Git status clean**
  ```bash
  git status  # Should show "nothing to commit"
  ```

- [ ] **Latest commits reviewed**
  ```bash
  git log --oneline -5  # Verify commits look correct
  ```

- [ ] **Shellcheck passing**
  ```bash
  shellcheck scripts/automation/pmo/*.sh
  ```

- [ ] **Configuration files valid**
  ```bash
  for f in scripts/automation/pmo/examples/.runner-config/*.yaml; do
    yamllint "$f" || echo "FAIL: $f"
  done
  ```

### B. COMPONENT HEALTH ✓

Run deployment validation:
```bash
./scripts/automation/pmo/deployment-validation.sh --phase=p0 --check=all
```

- [ ] **Ephemeral Workspace Manager**: Ready
- [ ] **Capability Store**: Valid
- [ ] **OTEL Tracing**: Operational
- [ ] **Fair Job Scheduler**: Valid
- [ ] **Drift Detector**: Operational

### C. DOCUMENTATION ✓

- [ ] **README.md updated**
  - Phase P0 section present
  - Phase P1 section present
  - Links working

- [ ] **Implementation docs complete**
  - [PHASE_P0_IMPLEMENTATION.md](docs/PHASE_P0_IMPLEMENTATION.md)
  - [PHASE_P0_QUICK_REFERENCE.md](docs/PHASE_P0_QUICK_REFERENCE.md)
  - [DEPLOYMENT_MONITORING_SETUP.md](docs/DEPLOYMENT_MONITORING_SETUP.md)

- [ ] **Configuration examples present**
  - `scripts/automation/pmo/examples/.runner-config/` directory exists
  - All YAML files valid and documented

### D. GIT REPOSITORY ✓

- [ ] **All commits pushed**
  ```bash
  git push
  ```

- [ ] **Remote in sync**
  ```bash
  git status  # Should show "branch is up to date"
  ```

- [ ] **GitHub issues accessible**
  - Visit: https://github.com/kushin77/self-hosted-runner/issues
  - Issues #1-5 visible and assigned

---

## 🏗️ INFRASTRUCTURE VALIDATION

### A. STAGING ENVIRONMENT ✓

- [ ] **Environment provisioned**
  - [ ] Compute instances deployed
  - [ ] Networking configured
  - [ ] Storage ready
  - [ ] Monitoring stack running (Prometheus, Grafana, Alertmanager)

- [ ] **Monitoring stack operational**
  ```bash
  # Check Prometheus
  curl -s http://prometheus:9090/api/v1/series | jq '.status'
  
  # Check Grafana
  curl -s http://grafana:3000/api/health | jq '.status'
  
  # Check Alertmanager
  curl -s http://alertmanager:9093/api/v1/alerts | jq '.status'
  ```

- [ ] **Network connectivity**
  ```bash
  # Test SSH to staging runners
  ssh -o ConnectTimeout=5 staging-runner-1 "echo OK"
  
  # Test API endpoints
  curl -s http://staging-api:8080/health
  ```

### B. PHASE P0 STAGING DEPLOYMENT ✓

- [ ] **Pre-deployment backup**
  ```bash
  # Backup any existing data
  tar -czf backups/pre-p0-deploy-$(date +%s).tar.gz /data
  ```

- [ ] **Dependencies installed**
  - [ ] Bash 4.0+: `bash --version`
  - [ ] curl: `which curl`
  - [ ] jq: `which jq`
  - [ ] Git: `which git`

- [ ] **Configuration staged**
  ```bash
  # Copy configuration to staging
  cp -r scripts/automation/pmo/examples/.runner-config staging/
  ```

- [ ] **Services ready**
  - [ ] systemd timer configured (if applicable)
  - [ ] cron jobs scheduled (if applicable)
  - [ ] Environment variables set
  - [ ] Secrets configured (no hardcoding!)

---

## 🔒 SECURITY VALIDATION

- [ ] **No credentials in code**
  ```bash
  grep -r "password\|secret\|token\|key" scripts/ --exclude-dir=.git || echo "No secrets found"
  ```

- [ ] **File permissions correct**
  ```bash
  # Check that only deployment account has write access
  ls -l scripts/automation/pmo/*.sh | grep -E "^-rwx" || echo "Permissions incorrect"
  ```

- [ ] **Audit logging enabled**
  - [ ] Drift detector audit trail enabled
  - [ ] Vault audit trail enabled (for P1)
  - [ ] Prometheus metrics exportable

- [ ] **RBAC configured**
  - [ ] Deployment account has minimum required permissions
  - [ ] Non-deployment accounts cannot modify configs
  - [ ] Read-only access for audit logs

---

## 📊 MONITORING SETUP

### A. METRICS COLLECTION ✓

- [ ] **Prometheus configured**
  ```bash
  # Verify scrape config
  cat scripts/automation/pmo/prometheus/prometheus.yml | grep "job_name"
  
  # Test scrape endpoint
  curl -s http://runner:8081/metrics | head -20
  ```

- [ ] **Alert rules loaded**
  ```bash
  # Verify alert rule files
  ls -la scripts/automation/pmo/prometheus/alert-rules-*.yaml
  
  # Validate YAML syntax
  yamllint scripts/automation/pmo/prometheus/alert-rules-*.yaml
  ```

- [ ] **Dashboards imported**
  - [ ] Phase P0 dashboard in Grafana
  - [ ] Phase P1 dashboard in Grafana (if P1 deployed)
  - [ ] Integration dashboard (if needed)

### B. ALERT ROUTING ✓

- [ ] **Alertmanager configured**
  ```bash
  # Verify alertmanager config
  cat scripts/automation/pmo/prometheus/alertmanager.yaml | grep "receiver:"
  ```

- [ ] **Slack webhooks tested**
  ```bash
  # Test Slack webhook
  curl -X POST $SLACK_WEBHOOK -d '{"text":"Deployment test"}'
  ```

- [ ] **PagerDuty integration tested** (if enabled)
  ```bash
  # Verify PagerDuty config
  grep "pagerduty" scripts/automation/pmo/prometheus/alertmanager.yaml
  ```

### C. LOG AGGREGATION ✓

- [ ] **Log directory created**
  ```bash
  mkdir -p scripts/automation/pmo/logs
  chmod 755 scripts/automation/pmo/logs
  ```

- [ ] **Log rotation configured** (for long-running deployments)
  ```bash
  # Setup logrotate for component logs
  cat > /etc/logrotate.d/phase-p0 <<EOF
  /var/log/phase-p0/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
  }
  EOF
  ```

---

## 🧪 VALIDATION TESTING

### A. UNIT TESTS ✓

- [ ] **Component tests passing**
  ```bash
  ./scripts/automation/pmo/deployment-validation.sh --phase=p0 --check=all
  ```
  Expected output: All checks pass, no failures

### B. INTEGRATION TESTS ✓

- [ ] **Phase P0 → Phase P1 integration**
  ```bash
  ./scripts/automation/pmo/deployment-validation.sh --phase=both --check=all
  ```

- [ ] **Workspace creation → Cleanup**
  ```bash
  # Create test workspace
  ./scripts/automation/pmo/ephemeral-workspace-manager.sh create \
    --parent=/tmp/test-parent \
    --job-id=test-job-$(date +%s)
  
  # Verify cleanup
  ./scripts/automation/pmo/ephemeral-workspace-manager.sh cleanup \
    --workspace=/tmp/test-parent/test-job-*
  ```

### C. LOAD TESTS ✓

- [ ] **Scheduling under load**
  ```bash
  # Simulate 100 job submissions
  for i in {1..100}; do
    echo "Submit job $i"
    # Job submission command
  done
  
  # Monitor queue depth
  watch -n 1 './scripts/automation/pmo/fair-job-scheduler.sh --status'
  ```

- [ ] **Workspace creation performance**
  ```bash
  # Create 10 workspaces and measure latency
  time (
    for i in {1..10}; do
      ./scripts/automation/pmo/ephemeral-workspace-manager.sh create \
        --parent=/tmp/load-test-$i \
        --job-id=load-test-$i
    done
  )
  ```

---

## 📋 PRE-DEPLOYMENT SIGN-OFF

### Requirements Met
- [ ] All code validation passed
- [ ] All component health checks passed
- [ ] All documentation complete and reviewed
- [ ] Staging environment ready
- [ ] Monitoring configured
- [ ] Security validation passed
- [ ] Integration tests passed
- [ ] Load tests successful
- [ ] Rollback procedure tested and ready

### Approvals
- [ ] Code review: Approved by: _________________ Date: _______
- [ ] Ops review: Approved by: _________________ Date: _______
- [ ] Security review: Approved by: _________________ Date: _______

### Final Sign-Off
**Deployment approved by**: ___________________  
**Date/Time**: _______________________________  
**Expected deployment window**: _______________  
**Rollback contact**: __________________________

---

## 🚀 GO/NO-GO DECISION

### Go Criteria (All must be YES)
- [ ] All validations passed: **YES / NO**
- [ ] Rollback tested: **YES / NO**
- [ ] Team notified: **YES / NO**
- [ ] On-call ready: **YES / NO**
- [ ] Monitoring live: **YES / NO**

### Decision
```
🟢 GO - Proceed with deployment
🟡 HOLD - Wait for resolution
🔴 NO-GO - Do not deploy
```

**Decision**: [ ] GO [ ] HOLD [ ] NO-GO

**Reason**: ________________________________________

**Decision made by**: ________________________________

---

## 📞 DEPLOYMENT CONTACTS

| Role | Name | Phone | Slack |
|------|------|-------|-------|
| Deployment Lead | | | |
| Platform On-Call | | | |
| Ops Escalation | | | |
| Security Contact | | | |

---

## 📝 POST-DEPLOYMENT

After deployment, complete the following:

- [ ] **Initial validation** (first 5 minutes)
  ```bash
  ./scripts/automation/pmo/deployment-validation.sh --phase=p0 --watch=true
  ```

- [ ] **Monitor metrics** (first 30 minutes)
  - Check Grafana dashboards for anomalies
  - Review error rate in logs
  - Verify alert channels working

- [ ] **Sanity checks** (first hour)
  - Test job submission
  - Verify workspace creation/cleanup
  - Check capability store discovery

- [ ] **Full validation** (first 24 hours)
  - Complete deployment validation suite
  - Review all metrics against baselines
  - Confirm zero regressions

- [ ] **Document results**
  - Update deployment log
  - Capture baseline metrics
  - Note any issues for follow-up

---

## 📚 REFERENCE DOCUMENTS

- [APPROVED_DEPLOYMENT.md](APPROVED_DEPLOYMENT.md) - Overall approval
- [DEPLOYMENT_MONITORING_SETUP.md](DEPLOYMENT_MONITORING_SETUP.md) - Monitoring guide
- [PHASE_P0_QUICK_REFERENCE.md](PHASE_P0_QUICK_REFERENCE.md) - Operator reference
- [PHASE_P0_IMPLEMENTATION.md](PHASE_P0_IMPLEMENTATION.md) - Complete guide

---

**Status**: ✅ **READY FOR DEPLOYMENT**  
**Last Updated**: March 4, 2026  
**Version**: 1.0

Use this checklist for every deployment. Customize as needed for your environment.
