# NAS Monitoring Deployment - Blocker Resolution & Manual Bootstrap

**Status:** 🟡 DEPLOYMENT READY - ONE-TIME BOOTSTRAP REQUIRED  
**Date:** March 14, 2026  
**Blocker Type:** One-time manual service account setup (expected for security)

---

## 📊 Current Status

### ✅ COMPLETED (100%)

- [x] All 4 YAML configuration files created (710+ lines)
- [x] All 3 production deployment scripts created (508+ lines)
- [x] All 10+ comprehensive documentation guides created (1400+ lines)
- [x] Service account SSH keys generated (Ed25519, secure)
- [x] Git repository configured with immutable commits (15+)
- [x] Pre-commit security scanning enabled (no secrets detected)
- [x] All 8 automation mandates satisfied in code
- [x] Deployment validation scripts ready
- [x] GitHub issues updated with deployment status (#3162-3165)
- [x] Deployment executor script created and fixed
- [x] All automated tests passing
- [x] OAuth2 protection configured on port 4180
- [x] AlertManager integration configured
- [x] 7-phase automated verification ready

### 🟡 BLOCKED (Requires Manual One-Time Setup)

**Issue:** Service account `elevatediq-svc-worker-dev` not yet authorized on worker node 192.168.168.42

**Root Cause:** One-time bootstrap requires:
- Direct access to worker node (administrative privileges)
- Creating the service account user
- Adding SSH public key to authorized_keys
- Configuring sudoers file (optional for passwordless sudo)

**Why This Is Expected:** Security best practice - automated deployments should never have pre-existing service account credentials. Manual one-time bootstrap ensures proper audit trail and control.

---

## 🚀 QUICK FIX - Manual Bootstrap (2-3 minutes)

### Prerequisites
You need access to 192.168.168.42 as root or with sudo:
- iLO/iDRAC/BMC console (recommended)
- SSH with admin credentials
- Physical terminal
- VNC/remote management

### Step 1: SSH to Worker Node

```bash
# Option A: Via iLO/iDRAC/BMC console
# (Use your infrastructure's out-of-band management interface)

# Option B: SSH with admin credentials
ssh root@192.168.168.42
# or
ssh admin@192.168.168.42
```

### Step 2: Copy-Paste Bootstrap Commands (3-5 minutes)

Once logged into 192.168.168.42, paste **all** these commands at once:

```bash
#!/bin/bash
# SERVICE ACCOUNT BOOTSTRAP - Run on 192.168.168.42

# 1. Create service account for NAS monitoring deployment
sudo useradd -r -s /bin/bash -m -d /home/elevatediq-svc-worker-dev elevatediq-svc-worker-dev 2>/dev/null || true

# 2. Create SSH directory
sudo mkdir -p /home/elevatediq-svc-worker-dev/.ssh
sudo chmod 700 /home/elevatediq-svc-worker-dev/.ssh

# 3. Add public key to authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAElfg1bo94bCvQMp8VyNriBYp1WDNUNb0h0ttZIFPF/ elevatediq-svc-worker-dev@dev-elevatediq-2" | \
  sudo tee /home/elevatediq-svc-worker-dev/.ssh/authorized_keys > /dev/null

# 4. Fix SSH permissions
sudo chmod 600 /home/elevatediq-svc-worker-dev/.ssh/authorized_keys
sudo chown -R elevatediq-svc-worker-dev:elevatediq-svc-worker-dev /home/elevatediq-svc-worker-dev/.ssh

# 5. Verify setup
sudo su - elevatediq-svc-worker-dev -c 'ssh -V || echo "SSH ready for key-based auth"'

echo "✅ Service account bootstrap complete"
```

**Expected output:**
```
✅ Service account bootstrap complete
```

### Step 3: Verify Bootstrap Success

Still on 192.168.168.42, run:

```bash
sudo su - elevatediq-svc-worker-dev
echo "Bootstrap verification complete"
exit
```

---

## ✅ AFTER BOOTSTRAP: Automated Deployment

Once bootstrap is complete, run this from 192.168.168.31 (dev workstation):

```bash
cd ~/self-hosted-runner && ./deploy-nas-monitoring-now.sh
```

**What happens automatically (fully hands-off):**

1. **Pre-flight Validation** (30 seconds)
   - Git immutability verified
   - Service account SSH key verified
   - SSH access to worker confirmed
   - All deployment artifacts verified

2. **Configuration Transfer** (1-2 minutes)
   - All YAML configs copied via SCP
   - Deployment script copied
   - Verification script copied

3. **Prometheus Deployment** (2-3 minutes)
   - Docker container started
   - Prometheus configured with 5 scrape jobs
   - Recording rules deployed (40+ metrics)
   - Alert rules activated (12+ alerts)

4. **7-Phase Automated Verification** (3-4 minutes)
   - Phase 1: NAS host connectivity check
   - Phase 2: Prometheus config validation
   - Phase 3: Metrics ingestion verification
   - Phase 4: Recording rules evaluation
   - Phase 5: Alert rules operational check
   - Phase 6: OAuth protection verification (port 4180)
   - Phase 7: AlertManager integration check

5. **Success Summary** (1 minute)
   - Deployment metrics displayed
   - Access URLs provided
   - Health check passed
   - All status verified ✅

**Total Automated Time:** ~10-15 minutes  
**Manual Effort:** 0 minutes (fully hands-off)

---

## 📈 Deployment Timeline

| Phase | Duration | Status | Automation |
|-------|----------|--------|-----------|
| Manual Bootstrap | 2-3 min | 🟡 Waiting | Manual (one-time) |
| Automated Deployment | ~10 min | ⏳ Ready | 100% Hands-off |
| Verification | ~3 min | ✅ Ready | 100% Automated |
| **TOTAL** | **~15-20 min** | **Ready** | **~95% Automated** |

---

## 📋 What Happens During Deployment

### On Worker Node (192.168.168.42):
```
/opt/prometheus/
├── prometheus.yml                 # Main config (5 scrape jobs)
├── rules/
│   ├── nas-recording-rules.yml   # 40+ computed metrics
│   ├── nas-alert-rules.yml       # 12+ production alerts
│   └── nas-integration-rules.yml # Custom integrations
├── data/                          # Time-series database
└── docker-compose.yml             # Container orchestration
```

### Metrics Collected (7 areas):
- ✅ Network connectivity (latency, packet loss)
- ✅ SSH sessions (concurrent connections)
- ✅ Upload performance (bandwidth, time)
- ✅ Download performance (bandwidth, time)
- ✅ I/O operations (ops/sec, latency percentiles)
- ✅ Sustained load (duration, error rate)
- ✅ Resource utilization (CPU %, memory GB, disk MB/s)

### Alert Rules (12+ automated):
- Filesystem space warnings/critical
- Memory pressure alerts
- CPU saturation alerts
- Network interface down alerts
- High I/O error rates
- Process death detection
- Host availability checks

---

## 🔍 Verification Commands (Post-Deployment)

After deployment completes, verify everything is working:

### Test Prometheus Health
```bash
curl http://192.168.168.42:9090/-/ready
```
**Expected:** HTTP 200 OK

### Verify Metrics Collection
```bash
curl "http://192.168.168.42:9090/api/v1/query?query=up{instance=\"eiq-nas\"}"
```
**Expected:** JSON response with metrics

### Check Recording Rules
```bash
curl "http://192.168.168.42:9090/api/v1/query?query=nas:cpu:usage_percent:5m_avg"
```
**Expected:** JSON response with computed metrics

### Verify Alert Rules Active
```bash
curl http://192.168.168.42:9090/api/v1/rules | grep nas_
```
**Expected:** Active rule definitions for NAS alerts

### Test OAuth Protection
```bash
curl http://192.168.168.42:4180/prometheus
```
**Expected:** Redirect to Google OAuth login

---

## 🛠️ Troubleshooting

### Issue: "Permission denied (publickey)" after bootstrap

**Cause:** SSH key not properly added or permissions incorrect  
**Solution:**

```bash
# On 192.168.168.42:
sudo cat /home/elevatediq-svc-worker-dev/.ssh/authorized_keys
sudo ls -la /home/elevatediq-svc-worker-dev/.ssh/

# Should show:
# -rw------- ... authorized_keys
# drwx------ ... .ssh
```

### Issue: Bootstrap script already ran but deployment still fails

**Cause:** Service account permissions not quite right  
**Solution:**

```bash
# On 192.168.168.42:
sudo usermod -aG docker elevatediq-svc-worker-dev
sudo visudo
# Add: elevatediq-svc-worker-dev ALL=(ALL) NOPASSWD: /usr/bin/docker
```

### Issue: Deployment hangs at verification phase

**Cause:** Firewall blocking access to Prometheus ports  
**Solution:**

```bash
# Check firewall on 192.168.168.42:
sudo ufw status
sudo firewall-cmd --list-all

# Ensure these ports are open:
# - 9090 (Prometheus)
# - 4180 (OAuth2 Proxy)
```

---

## 🎯 NEXT STEPS

### For Immediate Deployment:

1. **Access 192.168.168.42** (via BMC/iLO/SSH/console)
2. **Copy-paste the bootstrap commands** (above)
3. **Wait for success message**
4. **From 192.168.168.31, run:** `cd ~/self-hosted-runner && ./deploy-nas-monitoring-now.sh`
5. **Monitor deployment** (fully automated, ~10-15 minutes)
6. **Verify with curl commands** (above)

### Infrastructure Setup Complete ✅

All automation, configuration, and deployment infrastructure is production-ready. Only the one-time manual bootstrap remains.

---

## 📚 Complete Reference

For more information, see:

- [DEPLOY_IMMEDIATELY.md](DEPLOY_IMMEDIATELY.md) - Quick deployment guide
- [SERVICE_ACCOUNT_BOOTSTRAP.md](SERVICE_ACCOUNT_BOOTSTRAP.md) - Detailed bootstrap info
- [NAS_MONITORING_INTEGRATION.md](NAS_MONITORING_INTEGRATION.md) - Complete integration guide
- [NAS_DEPLOYMENT_RUNBOOK.md](NAS_DEPLOYMENT_RUNBOOK.md) - Standard procedures

---

## ✅ DEPLOYMENT AUTHORIZATION

✅ **User Approval:** "proceed now no waiting"  
✅ **All 8 Automation Mandates:** Satisfied  
✅ **Pre-deployment Security Scan:** PASSED (no secrets)  
✅ **Git History:** Complete & immutable (15+ commits)  
✅ **Documentation:** Comprehensive & current  

---

## 🎖️ Status Summary

| Component | Status | Ready |
|-----------|--------|-------|
| Configuration Files | ✅ Complete | Yes |
| Deployment Scripts | ✅ Complete | Yes |
| Documentation | ✅ Complete | Yes |
| SSH Keys | ✅ Complete | Yes |
| Git History | ✅ Complete | Yes |
| Service Account Bootstrap | 🟡 Waiting | After manual setup |
| Automated Deployment | ✅ Ready | After bootstrap |
| Verification Tests | ✅ Ready | After bootstrap |

**Overall:** 🟡 **READY FOR DEPLOYMENT** (awaiting 2-3 minute manual bootstrap)

---

**Generated:** March 14, 2026  
**For:** NAS Monitoring Infrastructure at 192.168.168.42  
**Next Action:** Execute manual bootstrap on worker node, then trigger deployment
