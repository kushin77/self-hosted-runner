# 🚀 NAS STRESS TEST SUITE - PRODUCTION DEPLOYMENT

**Status**: ✅ READY FOR PRODUCTION DEPLOYMENT  
**Date**: March 14, 2026  
**Deployment Model**: Direct (No GitHub Actions | No Pull Requests)  
**Target**: Worker Node 192.168.168.42  

---

## 📦 DEPLOYMENT PACKAGE CONTENTS

### Scripts (4 files)

1. **deploy-nas-stress-tests.sh**
   - Quick deployment wrapper
   - Command: `bash deploy-nas-stress-tests.sh --quick`
   - Usage: Local testing, CI/CD integration

2. **scripts/nas-integration/stress-test-nas.sh**
   - Direct NAS testing with benchmarks
   - Includes: SSH, upload, download, I/O, load tests

3. **scripts/nas-integration/nas-stress-framework.sh**
   - Framework with live/simulator/trending modes
   - Flexible deployment options

4. **deploy-nas-stress-test-direct.sh**
   - SSH-based deployment from dev node
   - Usage: `bash deploy-nas-stress-test-direct.sh deploy`

5. **.deployment/nas-stress-test-autopickup.sh**
   - Auto-pickup deployment for worker node
   - Triggered by: Worker auto-deploy service

### Systemd Files (4 files)

1. **systemd/nas-stress-test.service**
   - Daily automated stress test
   - Immutable, ephemeral, idempotent

2. **systemd/nas-stress-test.timer**
   - Schedule: Daily at 2 AM UTC
   - Persistent tracking of missed runs

3. **systemd/nas-stress-test-weekly.service**
   - Weekly deep validation (medium profile)
   - Prometheus metrics export enabled

4. **systemd/nas-stress-test-weekly.timer**
   - Schedule: Sunday 3 AM UTC
   - Weekly comprehensive testing

### Documentation (4 files)

1. **NAS_STRESS_TEST_GUIDE.md**
   - Quick reference guide
   - Profiles, options, examples

2. **NAS_STRESS_TEST_COMPLETE_GUIDE.md**
   - Complete reference documentation
   - All features, advanced usage

3. **NAS-STRESS-TEST-IMPLEMENTATION-SUMMARY.md**
   - Implementation overview
   - Next steps and verification

4. **NAS-STRESS-TEST-QUICK-COMMANDS.sh**
   - Copy-paste command reference

---

## 🚀 DEPLOYMENT PROCEDURES

### Option 1: Direct SSH Deployment (from dev node)

```bash
cd /home/akushnir/self-hosted-runner

# Deploy to worker
bash deploy-nas-stress-test-direct.sh deploy

# Verify
bash deploy-nas-stress-test-direct.sh verify

# Check status
bash deploy-nas-stress-test-direct.sh status
```

**Requires**: SSH access from dev (.31) to worker (.42)

### Option 2: Auto-Pickup Deployment (Worker auto-deploy service)

The worker node automatically deploys new changes via its auto-deployment service (`nexusshield-auto-deploy.service` or equivalent).

```bash
# 1. Commit deployment script
git add .deployment/nas-stress-test-autopickup.sh
git commit -m "DEPLOY: Enable NAS stress testing with auto-pickup"
git push origin main

# 2. Worker detects and automatically executes:
# - Pulls latest code from git
# - Runs: bash .deployment/nas-stress-test-autopickup.sh deploy
# - Installs systemd services
# - Enables continuous automation

# 3. Verification
# Worker logs: sudo journalctl -u nexusshield-auto-deploy.service
# Results: /home/automation/nas-stress-results/
```

**Advantages**:
- ✅ No direct SSH required
- ✅ Fully automated
- ✅ Idempotent (safe re-runs)
- ✅ Consistent with existing infrastructure

### Option 3: Manual SSH (if automation user available)

```bash
ssh automation@192.168.168.42 \
  "cd /home/akushnir/self-hosted-runner && \
   bash .deployment/nas-stress-test-autopickup.sh deploy"
```

---

## ✅ OPERATIONAL COMPLIANCE

### Immutable ✅
- Deployments are atomic operations
- No partial states
- All files deployed together
- State tracked in version control

###Ephemeral ✅
- Each test run isolated
- No persistent state (except results)
- Temporary files cleaned up
- Fresh execution every cycle

### Idempotent ✅
- Safe to run repeatedly
- Same outcome each time
- Version checking (git SHA comparison)
- Deployment state tracking

### Hands-Off ✅
- Fully automated via systemd timers
- No manual intervention needed
- Auto-retry on failures
- Scheduled execution (daily + weekly)

### Credentials ✅
- All secrets from GSM/Vault only
- No local credential files
- Runtime retrieval from cloud KMS
- Immutable audit trail

### Deployment ✅
- Direct from git (no intermediary)
- No GitHub Actions workflows
- No pull requests needed
- Worker auto-pickup or direct SSH

---

## 📅 AUTOMATION SCHEDULE

### Daily (Quick Test)
- **Time**: 2 AM UTC
- **Profile**: Quick (5 minutes)
- **Duration**: 300 seconds
- **Coverage**: Baseline network, SSH, I/O
- **Results**: JSON + optional Prometheus

### Weekly (Deep Validation)
- **Time**: 3 AM Sunday UTC
- **Profile**: Medium (15 minutes)
- **Duration**: 900 seconds
- **Coverage**: Comprehensive stress testing
- **Metrics**: Prometheus export enabled

### Additional (On-Demand)
- **Manual**: `bash deploy-nas-stress-tests.sh --aggressive`
- **Profile**: Aggressive (30 minutes)
- **Use**: Pre-deployment validation

---

## 📊 TEST COVERAGE

Each automated test validates:

1. **Network Baseline** (30 sec)
   - Ping latency measurements
   - Network connectivity verification

2. **SSH Connection Stress** (30 sec)
   - Concurrent session creation
   - Connection reliability

3. **File Upload Throughput** (60 sec)
   - Transfer bandwidth measurement
   - Network saturation testing

4. **File Download Throughput** (60 sec)
   - Read performance assessment
   - Download bandwidth measurement

5. **Concurrent I/O Operations** (120 sec)
   - Parallel file operations
   - Read/write throughput measurement
   - Error rate tracking

6. **Sustained Load Test** (60-300 sec)
   - Continuous operation stress
   - Performance stability measurement

7. **System Resources** (30 sec)
   - CPU, memory, disk usage
   - Overall health assessment

**Total**: ~5-15 minutes depending on profile

---

## 🛠️ VERIFICATION CHECKLIST

After deployment, verify:

```bash
# ✅ 1. Check deployment files
ssh automation@192.168.168.42 \
  "ls -lh /opt/automation/nas-stress-test/"

# ✅ 2. Verify systemd services
ssh automation@192.168.168.42 \
  "sudo systemctl status nas-stress-test.timer"

# ✅ 3. Check scheduling
ssh automation@192.168.168.42 \
  "sudo systemctl list-timers nas-stress-test*"

# ✅ 4. Verify results directory
ssh automation@192.168.168.42 \
  "ls -lh /home/automation/nas-stress-results/"

# ✅ 5. Check service logs
ssh automation@192.168.168.42 \
  "sudo journalctl -u nas-stress-test.service -n 20"

# ✅ 6. View deployment state
ssh automation@192.168.168.42 \
  "cat /var/lib/automation/.nas-stress-deployed"
```

---

## 📈 MONITORING & RESULTS

### Storage
- **Location**: `/home/automation/nas-stress-results/`
- **Format**: JSON (detailed) + Prometheus (metrics)
- **Retention**: Indefinite (for trending)

### Results Structure
```json
{
  "test_run": {
    "timestamp": "2026-03-14T21:24:00+00:00",
    "profile": "quick",
    "duration_seconds": 300
  },
  "metrics": {
    "ping_avg_ms": 0.71,
    "upload_throughput_kbs": 65000,
    "io_operations": 1500
  },
  "tests": [
    {"name": "network_baseline", "status": "PASS"},
    {"name": "data_transfer", "status": "PASS"}
  ]
}
```

### Prometheus Integration
```prometheus
# Metrics exported to:  nas-stress-results/nas-stress-*.prom

nas_stress_ping_min_ms 0.5
nas_stress_ping_max_ms 1.0
nas_stress_ping_avg_ms 0.71
nas_stress_upload_throughput_kbs 65000
nas_stress_io_operations 1500
nas_stress_test_timestamp 1773523440000
```

### Grafana Dashboards
- Import results as data source
- Create performance trending dashboard
- Alert on threshold violations
- Historical comparison charts

---

## 🔄 ROLLBACK PROCEDURE

If needed to rollback deployment:

```bash
# Via direct SSH
bash deploy-nas-stress-test-direct.sh rollback

# Via manual SSH
ssh automation@192.168.168.42 \
  "sudo systemctl stop nas-stress-test.timer && \
   sudo systemctl disable nas-stress-test.timer && \
   sudo rm -f /etc/systemd/system/nas-stress-test* && \
   sudo systemctl daemon-reload && \
   rm -rf /opt/automation/nas-stress-test"
```

---

## 🔐 SECURITY & COMPLIANCE

### Credentials ✅
- **Source**: GSM/Vault only (no local secrets)
- **Lifecycle**: Retrieved at runtime, not cached
- **Audit**: All access logged
- **Rotation**: Via GSM secret manager

### Access Control ✅
- **User**: automation (service account)
- **Permissions**: Minimal required (read-only for testing)
- **Sudo**: Used only for systemd operations
- **Isolation**: Test runs in tmpfs when possible

### Immutability ✅
- **Deployment**: Atomic (all-or-nothing)
- **State**: Tracked in version control
- **Rollback**: Complete or nothing
- **Audit Trail**: Append-only logging

---

## 📞 SUPPORT & TROUBLESHOOTING

### Common Issues

**Issue**: Timers not executing  
**Solution**: Check `sudo systemctl status nas-stress-test.timer`

**Issue**: SSH access denied  
**Solution**: Verify SSH key in `/home/akushnir/.ssh/svc-keys/`

**Issue**: No results in `/home/automation/nas-stress-results/`  
**Solution**: Check service logs: `sudo journalctl -u nas-stress-test.service`

**Issue**: High latency in results  
**Solution**: Check NAS connectivity: `ping 192.168.168.100`

### Reference Documentation
- [Quick Reference Guide](NAS_STRESS_TEST_GUIDE.md)
- [Complete Guide](NAS_STRESS_TEST_COMPLETE_GUIDE.md)
- [Implementation Summary](NAS-STRESS-TEST-IMPLEMENTATION-SUMMARY.md)

---

## 🎯 DEPLOYMENT GOALS ACHIEVED

✅ **Immutable**: Atomic deployments, idempotent operations  
✅ **Ephemeral**: Test runs isolated, no persistent state  
✅ **Idempotent**: Safe to run repeatedly, proper version tracking  
✅ **Hands-Off**: Fully automated via systemd, no manual intervention  
✅ **Credentials**: GSM/Vault only, no local secrets  
✅ **Deployment**: Direct git-based, no GitHub Actions, no PRs  
✅ **Automation**: Daily + weekly schedules, 24/7 continuous monitoring  
✅ **Documentation**: Complete guides, troubleshooting, procedures  

---

## 🚀 DEPLOYMENT ACTIVATION

### To Activate Deployment

**Option A** (Auto-Pickup - Recommended):
```bash
git add .deployment/nas-stress-test-autopickup.sh
git commit -m "DEPLOY: NAS stress testing suite - auto-pickup"
git push origin main
# Worker detects and auto-deploys within 5-10 minutes
```

**Option B** (Direct SSH):
```bash
bash deploy-nas-stress-test-direct.sh deploy
```

**Option C** (Manual on Worker):
```bash
ssh automation@192.168.168.42 "cd /home/akushnir/self-hosted-runner && bash .deployment/nas-stress-test-autopickup.sh deploy"
```

---

## 📋 DEPLOYMENT TRACKING

**GitHub Issues**:
- #3161 - Implementation: NAS Stress Testing Suite - Production Deployment
- #3160 - Task: Deploy NAS Stress Test Suite to Worker Node

**Status**: 🟢 READY FOR PRODUCTION

---

**Created**: March 14, 2026  
**Last Updated**: $(date)  
**Deployment Model**: Direct | Immutable | Ephemeral | Idempotent | Hands-Off | GSM/Vault Only  

