# Operations Runbook: NexusShield On-Premises

## Quick Reference

| Scenario | Command | Expected Result |
|----------|---------|-----------------|
| Deploy an update | `git push origin main` | Auto-deployed to .42 within 5 min |
| Rollback | `git revert HEAD && git push` | Previous version deployed, ~5 min |
| Check health | `curl http://192.168.168.42:5000/health` | HTTP 200 + JSON status |
| Scale up | `kubectl scale deploy/portal-api --replicas=5` | 5 running pods |
| View logs | `kubectl logs -n nexus-discovery <pod> -f` | Real-time logs streaming |
| Emergency restart | `kubectl rollout restart deployment/<name>` | Pods restart gracefully |
| Check status | `kubectl get pods -n nexus-discovery` | All pods Ready |

---

## 1. QUICK START

### First Time Setup

**On .42 (once):**
```bash
cd /home/akushnir/self-hosted-runner

# 1. Initialize infrastructure (creates Kubernetes cluster, labels, policies)
sudo ./infrastructure/on-prem-dedicated-host.sh --initialize

# 2. Validate setup
sudo ./infrastructure/on-prem-dedicated-host.sh --validate

# 3. Deploy services
sudo ./infrastructure/on-prem-dedicated-host.sh --deploy-services

# 4. Enable continuous deployment service
sudo systemctl start nexusshield-auto-deploy.service
sudo systemctl enable nexusshield-auto-deploy.service

# 5. Check status
sudo systemctl status nexusshield-auto-deploy.service
```

**On .31 (development):**
```bash
cd /home/akushnir/self-hosted-runner

# Clone if needed
git clone <repo-url>

# All work performed here; push triggers auto-deploy to .42
git add .
git commit -m "Feature: add feature X"
git push origin main  # Auto-deploys to .42
```

### Verify Setup Is Working

```bash
# From .31 (development):

# 1. SSH to .42 and check cluster
ssh 192.168.168.42
kubectl cluster-info
# Should show: Kubernetes control plane running, kube-dns running

# 2. Check pods
kubectl -n nexus-discovery get pods
# Should show: portal-api, frontend, nexus-engine, postgres, redis, prometheus, es pods

# 3. Check services
kubectl -n nexus-discovery get svc
# Should show: portal-api, frontend, kafka, postgres, redis

# 4. Check auto-deploy service
sudo systemctl status nexusshield-auto-deploy.service
# Should show: active (running)

# 5. Health check
curl http://localhost:5000/health
# Should return: {"status":"ok",...}
```

---

## 2. DEPLOYMENT WORKFLOWS

### Workflow 1: Normal Update

**Goal**: Deploy a code change to production

**Steps:**
```bash
# On .31 (development):
cd /home/akushnir/self-hosted-runner

# 1. Make changes
vim src/index.md  # (or use IDE)
# OR
git diff  # Review changes

# 2. Commit
git add .
git commit -m "Fix: issue description

- Change detail 1
- Change detail 2
- Fix #123"

# 3. Push (triggers auto-deploy)
git push origin main

# 4. Monitor deployment (optional)
ssh 192.168.168.42
watch kubectl -n nexus-discovery get pods
# Wait for all pods to be Ready (2-3 minutes)

# 5. Verify
curl http://192.168.168.42:5000/health
# Should return 200 OK

# 6. Done!
# Service automatically restarted with new code
```

**Expected Timeline:**
- Commit push: Immediate
- Auto-detect on .42: <1 min
- Deployment start: 1-2 min
- Health checks: 3-5 min
- Service live: 5-7 min total

### Workflow 2: Emergency Rollback

**Goal**: Revert to previous working version (security issue, data corruption, etc.)

**Steps:**
```bash
# On .31 (development):
cd /home/akushnir/self-hosted-runner

# 1. Identify last good commit
git log --oneline | head -10
# abc1234 (current - broken)
# def5678 (previous - working)
# ghi9012 (before that)

# 2. Create rollback commit
git revert HEAD  # Reverts abc1234
# Opens editor, review message, save

# 3. Push rollback
git push origin main

# 4. Monitor (on .42)
ssh 192.168.168.42
tail -f /var/log/nexusshield/audit-trail.jsonl
# Should show new deployment starting

watch kubectl -n nexus-discovery get pods
# Pods will terminate and restart with previous version

# 5. Verify rollback successful
curl http://192.168.168.42:5000/health
# Should return previous version info

# 6. Post-incident review
# Figure out what went wrong in abc1234
# Fix and reapply (do NOT revert the revert initially)
```

**Expected Timeline:**
- Rollback commit: <1 min
- Auto-deploy: <2 min
- Service live: 2-7 min total
- **Total downtime: Minimal (pods restart gracefully)**

### Workflow 3: Configuration Change

**Goal**: Update application configuration without changing code

**Steps:**
```bash
# On .31 (development):
cd /home/akushnir/self-hosted-runner

# 1. Update configuration
vim kubernetes/phase1-deployment.yaml
# Change replicas, resource limits, environment variables, etc.

# 2. Commit
git add kubernetes/
git commit -m "Config: increase portal-api replicas to 5"

# 3. Push (auto-deploys)
git push origin main

# 4. Monitor
kubectl -n nexus-discovery get deployments
# Should show updated replica count

# 5. Done!
# Kubernetes managed automatic rollout
# New pods created, old pods terminated gracefully
```

### Workflow 4: Database Schema Migration

**Goal**: Update database schema (carefully!)

**Steps:**
```bash
# IMPORTANT: For database changes, PLAN CAREFULLY
# Migrations must be backwards-compatible (handle old + new code)

# On .31 (development):
cd /home/akushnir/self-hosted-runner

# 1. Create database migration script
mkdir -p migrations/$(date +%Y%m%d)
cat > migrations/20250313/001_add_column_X.sql << 'EOF'
-- Migration: Add column X to users table
-- Date: 2025-03-13
-- Backwards compatible: Yes (new column is nullable with default)

ALTER TABLE users ADD COLUMN feature_flag BOOLEAN DEFAULT FALSE;
EOF

# 2. Add migration runner to deployment (if not already there)
# Ensure migrations run before application startup
# This is typically done in Kubernetes Job or init container

# 3. Commit migration + code
git add migrations/
git commit -m "DB: add feature_flag column to users table

- Create migration 001_add_column_X.sql
- Update application to use feature_flag in business logic
- Backwards compatible (old code still works)"

# 4. Push (auto-deploys)
git push origin main

# 5. Monitor migration
kubectl -n nexus-discovery logs -l app=portal-api -f | grep -i migration
# Should show: Migration successful, schema updated

# 6. Verify
kubectl exec -it postgres-0 -n nexus-discovery -- psql -U nexus_user -d nexusshield -c '\d users'
# Should show new column

# 7. Done!
```

---

## 3. MONITORING & TROUBLESHOOTING

### Monitor Current Status

```bash
# One-liner health check:
curl -s http://192.168.168.42:5000/health | jq .

# Expected output:
# {
#   "status": "ok",
#   "timestamp": "2025-03-13T10:15:22Z",
#   "services": {
#     "kubernetes": "ok",
#     "database": "ok",
#     "cache": "ok",
#     "broker": "ok"
#   }
# }
```

### View Pod Status

```bash
# All pods in deployment
kubectl -n nexus-discovery get pods

# Detailed pod info
kubectl -n nexus-discovery get pods -o wide

# Specific pod status
kubectl -n nexus-discovery describe pod <pod-name>

# Real-time pod changes
watch kubectl -n nexus-discovery get pods
```

### View Logs

```bash
# Last 50 lines
kubectl -n nexus-discovery logs <pod-name> --tail=50

# Real-time logs (like `tail -f`)
kubectl -n nexus-discovery logs <pod-name> -f

# All pods from deployment
kubectl -n nexus-discovery logs -l app=portal-api --all-containers=true

# Show timestamps
kubectl -n nexus-discovery logs <pod-name> --timestamps=true

# Show errors only
kubectl -n nexus-discovery logs <pod-name> | grep -i error
```

### Check Resource Usage

```bash
# CPU/memory per pod
kubectl -n nexus-discovery top pods

# CPU/memory per node
kubectl top nodes

# Persistent volume usage
kubectl -n nexus-discovery get pvc

# Storage status
kubectl -n nexus-discovery exec postgres-0 -- df -h /data/postgresql
```

### Common Issues & Fixes

#### Issue 1: Pod in CrashLoopBackOff

**Symptom:**
```
portal-api-abc123   0/1     CrashLoopBackOff   5          2m
```

**Troubleshoot:**
```bash
# 1. Check logs
kubectl -n nexus-discovery logs portal-api-abc123 --tail=20

# 2. Check pod events
kubectl -n nexus-discovery describe pod portal-api-abc123 | tail -20

# 3. Check resource requests vs node capacity
kubectl -n nexus-discovery describe pod portal-api-abc123 | grep -A 5 "Requests"
kubectl describe node <node-name> | grep -A 5 "Allocatable"

# 4. If resource issue: scale down replicas
kubectl -n nexus-discovery scale deployment portal-api --replicas=1

# 5. If code issue: check recent commits
git log --oneline | head -3
git show HEAD

# 6. Rollback if needed
git revert HEAD
git push origin main
```

#### Issue 2: Disk Space Full

**Symptom:**
```bash
kubectl -n nexus-discovery get events | grep -i "disk"
# ... Disk pressure ...
```

**Fix:**
```bash
# 1. SSH to .42
ssh 192.168.168.42

# 2. Check disk usage
sudo df -h

# 3. Clean up old logs
sudo journalctl --vacuum=100M

# 4. Clean up docker
sudo docker system prune -a

# 5. Check PVC usage
kubectl -n nexus-discovery exec postgres-0 -- du -sh /data/postgresql
# If >10GB: Archive old data + delete

# 6. Monitor going forward
watch df -h
```

#### Issue 3: Network Connectivity Issue

**Symptom:**
```bash
kubectl -n nexus-discovery logs portal-api-123 | grep -i "connection"
# ... failed to connect to database ... or ... connection timeout ...
```

**Troubleshoot:**
```bash
# 1. Check if service exists
kubectl -n nexus-discovery get svc

# 2. Check DNS resolution
kubectl -n nexus-discovery exec -it portal-api-123 -- nslookup postgres.nexus-discovery.svc.cluster.local

# 3. Check pod connectivity
kubectl -n nexus-discovery exec -it portal-api-123 -- nc -zv postgres 5432

# 4. Check network policies
kubectl -n nexus-discovery get networkpolicies
kubectl -n nexus-discovery describe networkpolicy <policy-name>

# 5. Temporarily relax network policy (if urgent)
kubectl -n nexus-discovery edit networkpolicy <policy-name>
# Remove selector or allow rule temporarily
# DANGER: This reduces security, only for debugging

# 6. Check pod IP
kubectl -n nexus-discovery get pods -o wide
# Should show IPAddress for each pod
```

#### Issue 4: Slow Deployment

**Symptom:**
```bash
# Deployment taking > 10 minutes
kubectl -n nexus-discovery get deployment portal-api -w
# Stuck at 0/3 ready
```

**Troubleshoot:**
```bash
# 1. Check pod status
kubectl -n nexus-discovery get pods -o wide

# 2. Check events
kubectl -n nexus-discovery get events --sort-by='.lastTimestamp' | tail -20

# 3. Check pull status (if image large)
kubectl -n nexus-discovery describe pod <pod-name> | grep -A 5 "Pulling"

# 4. Check readiness probe
kubectl -n nexus-discovery get pod <pod-name> -o yaml | grep -A 10 "readinessProbe"

# 5. If readiness probe failing too soon:
# - Increase initialDelaySeconds
# - Increase timeoutSeconds
# Edit: kubectl -n nexus-discovery edit deployment portal-api
```

#### Issue 5: Out of Memory

**Symptom:**
```
portal-api-123   1/1     Killed   5          1m  (OOMKilled)
```

**Fix:**
```bash
# 1. Check memory limits
kubectl -n nexus-discovery get pod portal-api-123 -o yaml | grep -A 5 "resources:"

# 2. Increase memory limit
kubectl -n nexus-discovery set resources deployment portal-api --limits=memory=2Gi

# 3. Reduce replicas to conserve memory
kubectl -n nexus-discovery scale deployment portal-api --replicas=2

# 4. Analyze memory usage
kubectl -n nexus-discovery top pods | grep portal-api

# 5. Profile application (if persistent issue)
# Check for memory leaks, increase JVM heap, etc.
```

### View Immutable Audit Trail

```bash
# All events
tail -100 /var/log/nexusshield/audit-trail.jsonl | jq .

# Filter by action
grep '"action":"deploy"' /var/log/nexusshield/audit-trail.jsonl | jq .

# Filter by timestamp (last 1 hour)
awk -v d="$(date -u -d '1 hour ago' +%s)" '\
  BEGIN { now=systime() } \
  { split($0, a, "\"timestamp\":\""); \
    ts=substr(a[2], 1, 19); \
    gsub(/-/, "", ts); gsub(/:/, "", ts); \
    if (ts+0 > d) print }' /var/log/nexusshield/audit-trail.jsonl | jq .

# For security incidents
tail -1000 /var/log/nexusshield/audit-trail.jsonl | jq 'select(.action=="secret.access")'
```

---

## 4. MAINTENANCE TASKS

### Daily Tasks (Do not skip!)

```bash
# 1. Check health (5 min)
curl http://192.168.168.42:5000/health

# 2. Review audit trail for anomalies (5 min)
ssh 192.168.168.42
tail -20 /var/log/nexusshield/audit-trail.jsonl | jq '.[] | {action, status, error}'

# 3. Check disk space (2 min)
kubectl -n nexus-discovery get pvc
df -h | grep nexusshield
```

### Weekly Tasks

```bash
# 1. Database backup verification (10 min)
# Verify backups are created every 4 hours
kubectl -n nexus-discovery exec postgres-0 -- ls -lah /data/postgresql/backups/ | tail -5

# 2. Review pod restarts (5 min)
kubectl -n nexus-discovery describe pod | grep "Restart Count" | sort -t: -k2 -rn | head -5
# If high restart count: investigate

# 3. Secret rotation status (5 min)
grep '"action":"secret.rotation"' /var/log/nexusshield/audit-trail.jsonl | tail -5 | jq .

# 4. Test emergency rollback (30 min)
# On non-production: git revert, verify rollback works, re-revert
git log --oneline | head -5
git revert HEAD
git push origin main
# Wait for deployment, verify health, then:
git revert HEAD  # Re-revert
git push origin main
```

### Monthly Tasks

```bash
# 1. Disaster recovery drill (2 hours)
# Simulated .42 failure:
# - Backup all critical data
# - Spin up new .42 image
# - Run: sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
# - Verify services come up from backup
# - Document actual recovery time

# 2. Security review (1 hour)
# - Audit network policies (should only allow minimal egress to cloud)
# - Audit RBAC (service accounts should have minimal permissions)
# - Audit secrets access log (should show no unusual access patterns)

# 3. Performance analysis (1 hour)
# - Review pod CPU/memory usage trends
# - Check database query performance
# - Identify slow operations

# 4. Cost review (30 min)
# - Review backup storage usage
# - Check for unused PersistentVolumes
# - Analyze resource requests vs actual usage
```

---

## 5. EMERGENCY PROCEDURES

### Emergency: Service Completely Down

**Goal**: Restore service ASAP

**Steps:**
```bash
# 1. Declare emergency (notify team)
# 2. Check if .42 is reachable
ping 192.168.168.42
# If no: Hardware failure, proceed to "Hardware Failure" section

# 3. Check cluster status
kubernetes cluster-info
# If broken: Reinitialize (see below)

# 4. Check pod status
kubectl -n nexus-discovery get pods
# If all healthy but service not responding: Check network connectivity

# 5. Restart services
kubectl -n nexus-discovery rollout restart deployment
# Wait 5 minutes

# 6. If still down: Rollback last deployment
git revert HEAD
git push origin main
# Wait 5-10 minutes

# 7. Last resort: Full cluster reinitialize
# (Only if nothing else works)
sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
# Recovery time: 15-30 minutes

# 8. Post-incident: Root cause analysis
# What went wrong? How to prevent?
```

### Emergency: Hardware Failure (.42 Down)

**Goal**: Restore on new hardware

**Steps:**
```bash
# 1. Ensure data safety
# - All state is in git
# - All secrets in cloud
# - Database backups automated (stored on cloud or backup node)
# - You should be able to lose .42 Hardware with zero data loss

# 2. Provision new .42 hardware
# (Hardware procurement, network config, OS install)
# Ensure: SSH access, sudo access, docker/kubectl pre-removed

# 3. Clone git repo on new .42
cd /home/akushnir/self-hosted-runner
git clone <repo-url>

# 4. Initialize infrastructure
sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
# This will:
#   - Create directories (immutable)
#   - Initialize Kubernetes cluster
#   - Deploy all manifests from git
#   - Connect to cloud backups
#   - Restore database from snapshot
#   - Start continuous deployment service

# 5. Monitor recovery
watch kubectl -n nexus-discovery get pods
# Wait for all pods to reach Ready state (5-15 min)

# 6. Verify data integrity
curl http://localhost:5000/health
# Spot-check recent data via API

# 7. Announce service restoration
# Document incident: what failed, how long to recover
```

### Emergency: Data Corruption

**Goal**: Restore from last known good state

**Steps:**
```bash
# 1. Immediate action: Pause deployments
# Don't let corrupted data spread
sudo systemctl stop nexusshield-auto-deploy.service

# 2. Assess damage
# What data got corrupted?
# When did it happen?
# Check audit trail
grep '"action":"db' /var/log/nexusshield/audit-trail.jsonl | jq '.[] | select(.status=="error")'

# 3. Restore from backup
# Find backup before corruption time
kubectl -n nexus-discovery exec postgres-0 -- ls -la /data/postgresql/backups/
# Select backup timestamp closest to (corruption time - 10 min)

# 4. Restore database
kubectl -n nexus-discovery exec postgres-0 -- \
  pg_restore -d nexusshield /data/postgresql/backups/backup-TIMESTAMP.dump

# 5. Verify restored data
kubectl -n nexus-discovery exec -it postgres-0 -- \
  psql -U nexus_user -d nexusshield -c "SELECT COUNT(*) FROM users;"

# 6. Resume deployments
sudo systemctl start nexusshield-auto-deploy.service

# 7. Root cause analysis
# How did corruption happen?
# Update validation/checks to prevent
```

### Emergency: Security Breach

**Goal**: Contain threat, rotate secrets, verify integrity

**Steps:**
```bash
# 1. Immediate action: Isolate if necessary
# If you think code is compromised:
sudo systemctl stop nexusshield-auto-deploy.service
# (Prevents auto-deployment of malicious code)

# 2. Identify what was compromised
# Secrets? Code? Data? Audit logs?
# Review immutable audit trail
tail -500 /var/log/nexusshield/audit-trail.jsonl | jq '.[] | select(.action=="secret.access")'

# 3. Rotate ALL secrets immediately
# Update in Vault, GSM, AWS, Azure
# (See Rotate Secrets in deployment workflows)

# 4. Review network policies
# Ensure pods cannot egress to unexpected networks
kubectl -n nexus-discovery get networkpolicies -o yaml

# 5. If code compromised: Rollback
git revert HEAD
git push origin main

# 6. Resume after all fixes
sudo systemctl start nexusshield-auto-deploy.service

# 7. Post-incident
# Full security audit, update RBAC/policies/secrets
```

---

## 6. SCALING & PERFORMANCE

### Horizontal Scaling (More Pods)

```bash
# Automatic scaling (Horizontal Pod Autoscaler)
# Min 2, Max 10 replicas based on CPU/Memory
kubectl -n nexus-discovery get hpa

# Manual scaling
kubectl -n nexus-discovery scale deployment portal-api --replicas=5

# View scaling events
kubectl -n nexus-discovery get events | grep -i scale
```

### Vertical Scaling (Bigger Pods)

```bash
# Increase resource limits for a pod
kubectl -n nexus-discovery set resources deployment portal-api \
  --requests=cpu=500m,memory=512Mi \
  --limits=cpu=2000m,memory=2Gi

# Note: This will trigger rolling restart (pods restart one-by-one)
watch kubectl -n nexus-discovery get pods
```

### Cost Optimization

```bash
# Right-size resource requests
kubectl -n nexus-discovery top pods
# Compare to requests/limits

# Delete unused PersistentVolumes
kubectl -n nexus-discovery get pvc
# Identify unused:
kubectl delete pvc <unused-pvc>

# Archive old logs
grep '"action":"deploy"' /var/log/nexusshield/audit-trail.jsonl \
  | awk '$0 < "2025-02-01"' > audit-trail-archive.jsonl
truncate -s 0 /var/log/nexusshield/audit-trail.jsonl  # Restart
```

---

## 7. CONTACTS & ESCALATION

| Issue | Contact | Priority | Response Time |
|-------|---------|----------|---|
| Service down | On-call engineer | P1 | <5 min |
| Data corruption | DB admin + on-call | P1 | <5 min |
| Security breach | Security team + on-call | P1 | <5 min |
| Performance degradation | Performance engineer | P2 | <30 min |
| Non-critical bugs | Dev team | P3 | <1 day |

**Escalation Path:**
1. Handle on-call engineer (P1-P2) → run diagnostics, mitigate
2. If > 1 hour: Escalate to team lead
3. If > 4 hours: Escalate to director + customer notification team
4. Keep immutable audit trail; all actions logged for post-incident review

---

## Quick Cheat Sheet

```bash
# GET STATUS
curl http://192.168.168.42:5000/health      # Overall health
kubectl get pods -n nexus-discovery          # Pod status
kubectl top pods -n nexus-discovery          # CPU/mem usage
df -h                                        # Disk usage

# DEPLOY UPDATE
git push origin main                         # Auto-deploys

# ROLLBACK
git revert HEAD && git push origin main

# SCALE
kubectl scale deployment <name> --replicas=5

# LOGS
kubectl logs <pod> -n nexus-discovery -f     # Stream logs
tail -f /var/log/nexusshield/audit-trail.jsonl  # Audit trail

# RESTART
kubectl rollout restart deployment/<name> -n nexus-discovery

# EMERGENCY STOP
sudo systemctl stop nexusshield-auto-deploy.service

# EMERGENCY RESUME
sudo systemctl start nexusshield-auto-deploy.service

# BACKUP CHECK
kubectl exec postgres-0 -- ls /data/postgresql/backups/

# DISASTER RECOVERY
sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
```

---

**Status**: 🟢 READY FOR OPERATIONS  
**Last Updated**: 2025-03-13  
**Maintained By**: Infrastructure Team
