# SSO Platform - Deployment Strategy & Execution Guide

**Date**: March 14, 2026  
**Status**: 🟢 Ready for Execution  
**Target**: 192.168.168.42 (On-Premises Worker Node)  

---

## Executive Summary

The complete SSO platform is ready to deploy to the on-premises worker node. This document explains:
- Three deployment approaches (ranked by suitability)
- How to select the right approach for your environment
- Step-by-step execution instructions
- Verification and troubleshooting

**Total deployment time**: 15-30 minutes (depending on approach)

---

## Three Deployment Approaches

### Approach 1: SSH-Based Full Orchestration ⭐⭐⭐ (RECOMMENDED)

**Prerequisites**:
- SSH access to `deploy@192.168.168.42`
- SSH key configured in `~/.ssh/authorized_keys`

**Advantages**:
- ✅ Handles all pre-flight checks
- ✅ Pre-configures on-prem storage
- ✅ Sets up systemd auto-deployment service
- ✅ Includes comprehensive audit logging
- ✅ Validates cluster health

**Disadvantages**:
- Requires SSH key setup
- Takes longer (includes storage prep)

**Command**:
```bash
cd /home/akushnir/self-hosted-runner
./scripts/sso/deploy-sso-on-prem.sh

# Output will show:
# [16:20:00] → Running preflight checks...
# [16:20:05] ✓ All required tools present
# [16:20:10] ✓ Worker node reachable
# [16:25:00] → Deploying TIER 1: Security Hardening...
# [16:33:00] ✓ TIER 1 complete
# [16:38:00] → Deploying TIER 2: Observability...
# [16:43:00] ✓ TIER 2 complete
# [16:48:00] → Deploying Core Services...
# [16:53:00] ✓ All deployments complete
```

**Timeline**: 25-30 minutes (includes storage setup)

---

### Approach 2: kubectl Direct Deployment ⭐⭐ (FALLBACK)

**Prerequisites**:
- kubectl CLI installed and on PATH
- kubeconfig configured (KUBECONFIG env or ~/.kube/config)
- Access to Kubernetes cluster API

**Advantages**:
- ✅ Fast (no SSH needed)
- ✅ No storage pre-configuration
- ✅ Works with any kubeconfig
- ✅ Dry-run mode available

**Disadvantages**:
- Doesn't set up on-prem storage (assumes existing)
- Doesn't enable auto-deployment service
- Requires pre-existing PersistentVolumes

**Commands**:
```bash
cd /home/akushnir/self-hosted-runner

# Preview changes (no actual deployment)
./scripts/sso/deploy-sso-kubectl.sh --dry-run

# Deploy to cluster
./scripts/sso/deploy-sso-kubectl.sh

# Force re-deployment (skip safety checks)
./scripts/sso/deploy-sso-kubectl.sh --force
```

**Timeline**: 15-20 minutes (manifest deployment only)

---

### Approach 3: Idempotent Deployment ⭐⭐⭐ (BEST FOR RE-DEPLOYMENT)

**Prerequisites**:
- kubectl access OR SSH access
- Same as Approach 1 or 2

**Advantages**:
- ✅ Safe to run N times (manifest hash tracking)
- ✅ Detects no-op deployments
- ✅ State tracking per phase
- ✅ Minimal output on no changes

**Disadvantages**:
- Slightly more verbose
- Requires state tracking files

**Commands**:
```bash
cd /home/akushnir/self-hosted-runner

# Deploy with idempotency
./scripts/sso/sso-idempotent-deploy.sh

# Dry-run mode
DRY_RUN=true ./scripts/sso/sso-idempotent-deploy.sh

# Force re-deployment
FORCE=true ./scripts/sso/sso-idempotent-deploy.sh

# View deployment state
cat .deployment-state/sso-*.state
```

**Timeline**: 15-30 minutes (first time), 2-3 minutes (no changes)

---

## Decision Matrix: Which Approach to Use?

| Situation | Approach | Reason |
|-----------|----------|--------|
| **First deployment, SSH available** | Approach 1 | Full setup with storage config + auto-deploy |
| **First deployment, kubectl only** | Approach 2 | Faster, simpler for existing clusters |
| **Re-deploying, making changes** | Approach 3 | Idempotent safety + state tracking |
| **Testing/preview** | Approach 2 + --dry-run | Risk-free preview before actual deploy |
| **Emergency, need fast deploy** | Approach 2 | Fastest time to production |

---

## Pre-Execution Checklist

Before running any deployment:

- [ ] **Verify git status**
  ```bash
  git status  # Should be clean or show only expected changes
  ```

- [ ] **Test connectivity**
  ```bash
  # For SSH-based (Approach 1):
  ssh -T deploy@192.168.168.42 "echo '✓ SSH works'"
  
  # For kubectl-based (Approach 2/3):
  kubectl cluster-info  # Should show cluster info
  ```

- [ ] **Check storage (if applicable)**
  ```bash
  ssh deploy@192.168.168.42 "df -h /mnt/nexus"  # Should show disk space > 50Gi
  ```

- [ ] **Verify manifests**
  ```bash
  ls -la kubernetes/manifests/sso/  # Should list all manifests
  ```

---

## Step-by-Step Execution

### Step 1: Choose Your Approach

Based on your environment, select from the three approaches above.

### Step 2: Run Pre-flight Checks

```bash
# Basic connectivity check
ping 192.168.168.42 -c 3

# kubectl connectivity (if using Approach 2/3)
kubectl get nodes

# SSH connectivity (if using Approach 1)
ssh deploy@192.168.168.42 "hostname"
```

### Step 3: Execute Deployment

```bash
# Navigate to repo
cd /home/akushnir/self-hosted-runner

# Example: Using Approach 1 (SSH-based)
./scripts/sso/deploy-sso-on-prem.sh

# OR Example: Using Approach 2 (kubectl direct)
./scripts/sso/deploy-sso-kubectl.sh
```

Monitor the output for progress and any errors.

### Step 4: Monitor Deployment

```bash
# In separate terminal, watch pods
kubectl get pods -n keycloak -w

# Or check status periodically
kubectl get pods -n keycloak
kubectl get svc -n keycloak
kubectl get pvc -n keycloak
```

### Step 5: Verify Success

After deployment completes (15-30 min):

```bash
# Check all pods running
kubectl get pods -n keycloak --no-headers | grep "Running"

# Check services
kubectl get svc -n keycloak

# Test Keycloak API
kubectl port-forward svc/keycloak 8080:8080 -n keycloak &
curl http://localhost:8080/auth/health/ready

# Test OAuth2-Proxy
kubectl port-forward svc/oauth2-proxy 5000:5000 -n oauth2-proxy &
curl http://localhost:5000/api/v1/health

# Verify storage
kubectl get pvc -n keycloak
kubectl get pv

# Check audit trail
tail -f /mnt/nexus/audit/sso-audit-trail.jsonl  # Requires SSH access
```

---

## Post-Deployment Steps

### 1. Run Integration Tests

```bash
./scripts/testing/integration-tests.sh

# Expected output:
# ✓ Test 1: Auth flow - PASS
# ✓ Test 2: Token validation - PASS
# ✓ Test 3: RBAC enforcement - PASS
# ✓ Test 4: Secrets retrieval - PASS
# ✓ Test 5: Database failover - PASS
# [10 tests] - ALL PASSING
```

### 2. Access Dashboards

```bash
# Grafana (monitoring)
kubectl port-forward svc/grafana 3000:80 -n keycloak
# Open https://localhost:3000

# Keycloak Admin Console
kubectl port-forward svc/keycloak 8080:8080 -n keycloak
# Open https://localhost:8080/auth/admin

# Prometheus (metrics)
kubectl port-forward svc/prometheus 9090:9090 -n keycloak
# Open https://localhost:9090
```

### 3. Enable Auto-Deployment (SSH-based only)

```bash
ssh deploy@192.168.168.42 "sudo systemctl enable nexusshield-sso-deploy.service"
ssh deploy@192.168.168.42 "sudo systemctl start nexusshield-sso-deploy.service"

# Verify auto-deployment is running
ssh deploy@192.168.168.42 "sudo systemctl status nexusshield-sso-deploy.service"
```

### 4. Update GitHub Issues

```bash
# Mark issues as in-progress or completed
# Issue #3058: SSO Platform - main tracking
# Issue #3059: TIER 1 Security - complete
# Issue #3060: TIER 2 Observability - complete
# Issue #3061: Deployment Execution - complete
```

---

## Deployment Logs

All deployments log to:
- **Stdout**: Real-time deployment progress
- **Audit Trail**: `/mnt/nexus/audit/sso-audit-trail.jsonl` (on-prem)
- **Local Logs**: `/tmp/sso-deployment-*.log` (deployment machine)

View logs:
```bash
# Real-time deployment progress
tail -f /tmp/sso-deployment-*.log

# After deployment - full log
cat /tmp/sso-deployment-*.log

# Audit trail (SSH required)
ssh deploy@192.168.168.42 "tail -f /mnt/nexus/audit/sso-audit-trail.jsonl"
```

---

## Troubleshooting

### Issue 1: SSH Connection Failed

**Error**: `Cannot SSH to worker node (deploy@192.168.168.42)`

**Solutions**:
1. Check SSH key installed: `ssh-copy-id deploy@192.168.168.42`
2. Use Approach 2 (kubectl) instead of Approach 1
3. Verify network connectivity: `ping 192.168.168.42`

### Issue 2: kubectl Cannot Connect to Cluster

**Error**: `The connection to the server localhost:8080 was refused`

**Solutions**:
1. Check kubeconfig: `echo $KUBECONFIG`
2. Verify cluster running: `ssh deploy@192.168.168.42 "kubectl cluster-info"`
3. Configure kubeconfig from worker: `scp deploy@192.168.168.42:~/.kube/config ~/.kube/config`

### Issue 3: Storage Not Available

**Error**: `PersistentVolumeClaim...Pending`

**Solutions**:
1. Check storage exists: `ssh deploy@192.168.168.42 "ls -la /mnt/nexus"`
2. Run storage setup: `ssh deploy@192.168.168.42 "mkdir -p /mnt/nexus/sso-data"`
3. Use Approach 1 to auto-configure storage

### Issue 4: Pods Stuck in Pending

**Error**: `kubectl get pods` shows pods in `Pending` state

**Solutions**:
```bash
# Check events
kubectl get events -n keycloak --sort-by='.lastTimestamp'

# Describe pod
kubectl describe pod <pod-name> -n keycloak

# Check node capacity
kubectl top nodes

# Check storage claims
kubectl get pvc -n keycloak
```

### Issue 5: Deployment Hangs

**Error**: Deployment script seems stuck for > 10 minutes

**Solutions**:
1. Check for network issues: `ping 192.168.168.42`
2. Monitor in separate terminal: `kubectl get pods -n keycloak -w`
3. Cancel script (Ctrl+C) and use alternative approach
4. Check logs: `tail -f /tmp/sso-deployment-*.log`

---

## Verification Checklist

After deployment succeeds, verify all items:

- [ ] All pods running: `kubectl get pods -n keycloak | grep Running`
- [ ] No pods in error: `kubectl get pods -n keycloak | grep -c Error || echo 0`
- [ ] Services ready: `kubectl get svc -n keycloak | grep -v "NAME"`
- [ ] PVC mounted: `kubectl get pvc -n keycloak | grep "Bound"`
- [ ] Keycloak responds: `curl http://localhost:8080/auth/health/ready`
- [ ] OAuth2-Proxy responds: `curl http://localhost:5000/api/v1/health`
- [ ] Prometheus scraping: Grafana shows metrics
- [ ] Integration tests pass: All 10/10 passing
- [ ] Audit trail recording: Events in `/mnt/nexus/audit/sso-audit-trail.jsonl`
- [ ] Auto-deployment ready: `systemctl status nexusshield-sso-deploy.service`

---

## Performance Targets

After successful deployment, system should achieve:

| Metric | Target | How to Verify |
|--------|--------|----------------|
| Availability | 99.9% | `kubectl top nodes` - no resource pressure |
| Response Time (p95) | < 200ms | Grafana "API Latency" dashboard |
| Cache Hit Rate | 85%+ | Grafana "Redis" dashboard |
| Error Rate | < 0.1% | Prometheus query: `rate(http_errors_total[5m])` |
| DB Replication Lag | < 1s | PostgreSQL Patroni status |

---

## Rollback Procedure

If deployment needs to be reverted:

```bash
# Option 1: Revert git commit (if using auto-deploy)
git revert HEAD
git push  # Auto-deploys previous version in 5-10 min

# Option 2: Manual service deletion
kubectl delete namespace keycloak
kubectl delete namespace oauth2-proxy

# Option 3: Using idempotent script with -force-revert
FORCE_REVERT=true ./scripts/sso/sso-idempotent-deploy.sh
```

---

## Success Indicators

Deployment is successful when:

✅ All pods in `keycloak` namespace are `Running`  
✅ All pods in `oauth2-proxy` namespace are `Running`  
✅ Services have ClusterIP addresses assigned  
✅ PersistentVolumeClaims are `Bound` to PersistentVolumes  
✅ Keycloak responds to health checks  
✅ OAuth2-Proxy responds to health checks  
✅ Prometheus is scraping metrics from all targets  
✅ Grafana dashboards display metrics  
✅ Integration tests pass (10/10)  
✅ Audit trail recording events  

---

## Support & Escalation

**For SSH Issues**: Check SSH key setup or use Approach 2 (kubectl)  
**For kubectl Issues**: Verify kubeconfig or re-download from worker node  
**For Storage Issues**: Use Approach 1 to auto-configure  
**For Deployment Issues**: Check logs in `/tmp/sso-deployment-*.log`  

---

## Files Used in Deployment

- **Orchestrators**:
  - `scripts/sso/deploy-sso-on-prem.sh` (450 lines)
  - `scripts/sso/sso-idempotent-deploy.sh` (400 lines)
  - `scripts/sso/deploy-sso-kubectl.sh` (350 lines) - NEW

- **Manifests** (15 files in `kubernetes/manifests/sso/`):
  - Network policies, RBAC, Pod security
  - PostgreSQL HA, Redis, PgBouncer
  - Prometheus, Grafana, monitoring
  - Keycloak, OAuth2-Proxy, Ingress

- **Documentation**:
  - `SSO_ONPREM_DEPLOYMENT.md` (3000+ words)
  - `SSO_ONPREM_DEPLOYMENT_FINAL_SUMMARY.md` (comprehensive guide)
  - *This file*: `SSO_DEPLOYMENT_STRATEGY.md`

---

## Related GitHub Issues

- **#3058**: SSO Platform - Deploy on-premises (main issue)
- **#3059**: TIER 1: Security Hardening - On-Premises
- **#3060**: TIER 2: Observability & Performance - On-Premises
- **#3061**: Deployment Execution & Verification

---

## Next Steps

1. **Choose deployment approach** based on your environment
2. **Run pre-flight checks** to verify connectivity
3. **Execute deployment** (15-30 minutes)
4. **Verify success** using checklist above
5. **Run integration tests** to confirm functionality
6. **Enable auto-deployment** (if using Approach 1)
7. **Update GitHub issues** with completion status

---

**Status**: 🟢 Production Ready  
**Commit**: 11586e8cf (SSO infrastructure)  
**Date**: March 14, 2026  
**Target**: 192.168.168.42  
**Model**: On-Premises | Immutable | Ephemeral | Idempotent
