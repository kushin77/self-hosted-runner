# SSO Platform - On-Premises Worker Node Deployment

## Status: ✅ Production Ready for On-Premises Deployment

**Deployment Target**: 192.168.168.42 (Worker Node)  
**Model**: Immutable | Ephemeral | Idempotent | No Cloud Services  
**Storage**: /mnt/nexus/sso-data (on-prem NAS)  
**Date**: March 14, 2026

---

## Deployment Architecture

### Infrastructure Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Worker Node: 192.168.168.42                                │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  TIER 1: Security Hardening (On-Premises)             │ │
│  │  • Network Policies (zero-trust, local only)           │ │
│  │  • RBAC (least-privilege)                             │ │
│  │  • PostgreSQL HA (3-node Patroni)                     │ │
│  │  • Pod Security Standards (non-root, read-only FS)    │ │
│  │  Storage: /mnt/nexus/sso-data (iSCSI/NAS)            │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  TIER 2: Observability (On-Premises Monitoring)        │ │
│  │  • Prometheus (local metrics)                          │ │
│  │  • Grafana (10 dashboards)                             │ │
│  │  • Redis Cache HA (3-node)                             │ │
│  │  • PgBouncer Connection Pooling                        │ │
│  │  Storage: /mnt/nexus/sso-data/monitoring              │ │
│  └────────────────────────────────────────────────────────┘ │
│                            ↓                                  │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Core SSO Services                                     │ │
│  │  • Keycloak (Identity Provider)                        │ │
│  │  • OAuth2-Proxy (API Gateway)                          │ │
│  │  • Ingress (On-Premises Load Balancer)                 │ │
│  │  Storage: /mnt/nexus/sso-data/keycloak               │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Audit Trail: /mnt/nexus/audit/sso-audit-trail.jsonl        │
│  (Append-only, immutable, 7-year retention)                  │
│                                                               │
│  Auto-Deployment: systemd service (git-triggered)            │
│  (No GitHub Actions, direct deployment)                      │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Clients (Internal Network)
    ↓
Ingress (192.168.168.42:443)
    ↓
OAuth2-Proxy (API Gateway)
    ↓
Keycloak (Identity Provider)
    ↓
PostgreSQL HA (3-node replica set)
    ↓
On-Premises Storage (/mnt/nexus/sso-data)
    ↓
Audit Trail + Backups (append-only)
```

### Secrets Management (Cloud-Only)

```
On-Premises Services DO NOT store secrets locally:
    ↓
Pod needs secret → Check 5-min in-memory cache
    ↓
Cache miss → Query cloud secret store (in secure order):
  1. HashiCorp Vault (preferred)
  2. Google Secret Manager (GSM)
  3. AWS Secrets Manager
  4. Azure Key Vault
    ↓
Secret pulled, cached in-memory (5 min TTL)
    ↓
All access logged to immutable audit trail
```

---

## Files Delivered

### Deployment Scripts (3 new files)

1. **scripts/sso/deploy-sso-on-prem.sh** (450 lines)
   - Complete end-to-end on-premises deployment
   - Pre-flight checks (connectivity, storage, cluster)
   - TIER 1-2 deployment with on-prem storage
   - Worker node synchronization
   - Auto-deployment service setup
   - Health verification

2. **scripts/sso/sso-idempotent-deploy.sh** (400 lines)
   - Idempotent deployment (safe to run N times)
   - Manifest hash-based change detection
   - State tracking for each phase
   - Dry-run mode for validation
   - Append-only audit logging
   - Automatic cleanup of failed pods

3. **Infrastructure Manifests** (Pre-existing, adapted for on-prem)
   - Network policies (local traffic only)
   - RBAC (least-privilege)
   - PostgreSQL HA (replicas on worker node)
   - Observability stack
   - Core SSO services

---

## Deployment Process

### Phase 1: Pre-Flight Checks (2 minutes)

```bash
./scripts/sso/deploy-sso-on-prem.sh
```

**Validates**:
- ✅ kubectl available and configured
- ✅ Network connectivity to worker node (192.168.168.42)
- ✅ SSH access to worker node
- ✅ Storage paths available (/mnt/nexus/sso-data)
- ✅ Kubernetes cluster connectivity
- ✅ On-premises registry availability

### Phase 2: On-Premises Storage Setup (1 minute)

**Creates**:
- ✅ PersistentVolume (hostPath to /mnt/nexus/sso-data)
- ✅ PersistentVolumeClaim (100Gi)
- ✅ Storage directories with proper permissions

### Phase 3: TIER 1 Security Hardening (8 minutes)

**Deploys**:
- ✅ Network policies (zero-trust, deny-all default)
- ✅ RBAC (per-component service accounts)
- ✅ PostgreSQL HA (3-node StatefulSet)
  - Pod 0: Primary (read/write)
  - Pod 1-2: Replicas (read-only + standby)
  - Patroni for automatic failover
  - WAL archiving for PITR

### Phase 4: TIER 2 Observability (5 minutes)

**Deploys**:
- ✅ Prometheus (metrics collection)
- ✅ Grafana (10 pre-configured dashboards)
- ✅ SLO rules (20+ metrics with alerting)
- ✅ Redis HA cache (3-node)
- ✅ PgBouncer connection pooling

### Phase 5: Core SSO Services (5 minutes)

**Deploys**:
- ✅ Keycloak (OIDC identity provider)
- ✅ OAuth2-Proxy (API gateway)
- ✅ Ingress (on-premises load balancer)

### Phase 6: Worker Node Sync (2 minutes)

**Rsync to Worker**:
- ✅ All manifests → /opt/nexusshield/sso/infrastructure/
- ✅ All scripts → /opt/nexusshield/sso/scripts/
- ✅ Client examples → /opt/nexusshield/sso/examples/
- ✅ Documentation → /opt/nexusshield/sso/docs/

### Phase 7: Auto-Deployment Service Setup (1 minute)

**Creates**:
- ✅ systemd service (nexusshield-sso-deploy.service)
- ✅ Auto-deploy script (detects git changes, redeploys)
- ✅ State tracking (/var/lib/nexusshield/sso-deployment)
- ✅ Audit logging to /mnt/nexus/audit/

**Total Deployment Time**: ~25-30 minutes

---

## Quick Start

### 1. Deploy Complete Platform

```bash
cd /home/akushnir/self-hosted-runner

# Run deployment orchestrator
chmod +x scripts/sso/deploy-sso-on-prem.sh
./scripts/sso/deploy-sso-on-prem.sh
```

### 2. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n keycloak
kubectl get pods -n oauth2-proxy

# Verify storage
kubectl get pvc -n keycloak

# Check audit trail
tail -f /mnt/nexus/audit/sso-audit-trail.jsonl

# Test API endpoint
curl http://192.168.168.42:5000/api/v1/health
```

### 3. Run Integration Tests

```bash
./scripts/testing/integration-tests.sh
```

### 4. Access Services

```bash
# Keycloak admin console
kubectl port-forward -n keycloak svc/keycloak 8080:8080
# http://localhost:8080/auth/admin

# Grafana dashboards
kubectl port-forward -n keycloak svc/grafana 3000:80
# http://localhost:3000

# Prometheus metrics
kubectl port-forward -n keycloak svc/prometheus 9090:90
# http://localhost:9090
```

---

## Key Features

### ✅ Immutability
- No mutable state on worker node
- All settings in Kubernetes manifests (version-controlled)
- Read-only filesystems where possible
- Append-only audit trail (never deleted, only appended)

### ✅ Ephemeralness  
- Pod failures cause automatic replacement
- Graceful shutdown with connection draining
- No attached state (all state in PostgreSQL)
- Safe to restart any component at any time

### ✅ Idempotency
- Manifest hash-based change detection
- State tracking per deployment phase
- Safe to run deployment script N times
- Same result regardless of execution count

### ✅ No Cloud Services (Pure On-Premises)
- ✅ No GKE (local Kubernetes cluster)
- ✅ No Google Cloud Storage (local NAS at /mnt/nexus)
- ✅ No Google Secret Manager (vault integration only)
- ✅ No Cloud Monitoring (local Prometheus)
- ✅ Secrets from cloud sources only (HashiCorp Vault, GSM, AWS, Azure)

### ✅ Zero GitHub Actions
- Git push triggers auto-deployment on worker node
- Direct deployment (systemd service monitors git)
- No GitHub Actions runners required
- Fast feedback loop (5-10 minutes from push to production)

### ✅ Direct Deployment
- No Pull Requests needed
- No GitHub Actions gating
- Changes committed to main branch auto-deploy
- Immutable audit trail tracks all deployments

---

## Operational Procedures

### Manual Deployment (Idempotent)

```bash
# Run deployment script (safe to repeat)
./scripts/sso/sso-idempotent-deploy.sh

# Dry-run to see what would change
DRY_RUN=true ./scripts/sso/sso-idempotent-deploy.sh

# Force re-deployment even if no changes
FORCE=true ./scripts/sso/sso-idempotent-deploy.sh
```

### Automatic Continuous Deployment

```bash
# On worker node:
sudo systemctl start nexusshield-sso-deploy.service
sudo systemctl status nexusshield-sso-deploy.service

# Watch deployment logs
sudo journalctl -u nexusshield-sso-deploy.service -f

# Disable auto-deployment (emergency)
sudo systemctl stop nexusshield-sso-deploy.service
```

### Scaling Replicas

```bash
# Scale Keycloak to 5 replicas
kubectl scale deployment keycloak -n keycloak --replicas=5

# Scale OAuth2-Proxy to 3 replicas
kubectl scale deployment oauth2-proxy -n oauth2-proxy --replicas=3

# Check HPA status
kubectl get hpa -n keycloak
```

### Database Operations

```bash
# Connect to PostgreSQL primary
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres-secret -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak

# Backup database
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres-secret -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  pg_dump -U keycloak keycloak | gzip > /mnt/nexus/backups/sso/keycloak_$(date +%s).sql.gz

# Check replication status
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres-secret -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

### Disaster Recovery

```bash
# RTO: < 15 minutes
# RPO: < 1 hour (daily backups)

# Restore from backup
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres-secret -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  gunzip -c /mnt/nexus/backups/sso/keycloak_*.sql.gz | \
  psql -U keycloak keycloak

# Manual failover (if needed)
kubectl delete pod keycloak-postgres-0 -n keycloak
# Wait for Patroni to promote a replica (30 seconds)
kubectl get pods -n keycloak -watch
```

---

## Monitoring & Observability

### 10 Pre-Configured Grafana Dashboards

1. **Keycloak Status** - Auth metrics, user count, token generation
2. **OAuth2-Proxy** - Request rate, latency, auth denials
3. **PostgreSQL Performance** - Query latency, replication lag
4. **Redis Cache** - Hit rate, memory, evictions
5. **Kubernetes Resources** - CPU, memory, disk I/O
6. **Network Flows** - Bandwidth, packet loss
7. **Security Events** - Auth failures, policy violations
8. **SLO Progress** - Availability %, latency p99, error rate
9. **On-Premises Storage** - Disk usage, I/O performance
10. **Audit Trail** - Deployment history, user actions

### Key Metrics

```promql
# Request rate (requests/second)
rate(keycloak_http_requests_total[5m])

# 99th percentile latency
histogram_quantile(0.99, rate(keycloak_http_request_duration_seconds_bucket[5m]))

# Error rate (% of requests failing)
rate(keycloak_http_requests_failed_total[5m])

# Cache hit ratio
rate(redis_keyspace_hits_total[5m]) / 
  (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Storage utilization
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

### Alerting Rules

- 🔴 **Critical**: Error rate > 1%, Availability < 99.8%, API latency p99 > 1s
- 🟠 **Warning**: Error rate > 0.5%, Availability < 99.95%, API latency p99 > 500ms
- 🟡 **Info**: Replica lag > 100ms, Cache hit rate < 80%, Disk usage > 85%

---

## Audit & Compliance

### Immutable Audit Trail

```bash
# Append-only JSON Lines format (never deleted)
tail -f /mnt/nexus/audit/sso-audit-trail.jsonl

# Example entries:
{"timestamp":"2026-03-14T10:30:00Z","event":"deployment_started","phase":"tier1","user":"deploy"}
{"timestamp":"2026-03-14T10:35:30Z","event":"deployment_complete","user":"deploy"}
{"timestamp":"2026-03-14T10:36:00Z","event":"postgres_pod_0_ready","containers":3}
```

### Event Tracking

- ✅ Deployment start/completion
- ✅ Pod creation/deletion/restart
- ✅ Storage mount/unmount
- ✅ Secret access (with access pattern logging)
- ✅ User authentication successes/failures
- ✅ Configuration changes
- ✅ Backup creation/restore
- ✅ Manual interventions

### 7-Year Retention

```bash
# Backup audit trail monthly
cron job: "0 0 1 * * tar -czf /mnt/nexus/audit/archive/sso-audit-$(date +\%Y\%m).tar.gz /mnt/nexus/audit/*.jsonl"

# Verify immutability (no modifications allowed)
sudo chattr +a /mnt/nexus/audit/  # Append-only mode (Linux)
```

---

## Constraints & Best Practices

### Hard Constraints (Non-Negotiable)

1. ✅ **On-Premises Only** - 192.168.168.42 only (NEVER cloud compute)
2. ✅ **No Cloud State** - All state in PostgreSQL on-prem (NEVER cloud databases)
3. ✅ **Secrets from Cloud** - Only cloud secret stores (Vault, GSM, AWS, Azure)
4. ✅ **No GitHub Actions** - Direct deployment only
5. ✅ **Immutable Infrastructure** - Append-only state tracking
6. ✅ **Ephemeral Containers** - Safe to replace at any time
7. ✅ **Idempotent Operations** - Safe to run N times

### Best Practices Implemented

- ✅ Network policies (zero-trust, deny-all default)
- ✅ RBAC (least-privilege per service)
- ✅ Pod Security Standards (non-root, read-only FS)
- ✅ Resource limits (CPU, memory)
- ✅ Health checks (liveness, readiness probes)
- ✅ Graceful shutdown (termination grace period)
- ✅ Distributed tracing (OTEL integration)
- ✅ Comprehensive logging (structured JSON)
- ✅ Metrics collection (Prometheus)
- ✅ SLO tracking (99.9% availability target)

---

## Troubleshooting

### Pods Not Starting

```bash
# Check pod logs
kubectl logs keycloak-0 -n keycloak -f

# Describe pod for events
kubectl describe pod keycloak-0 -n keycloak

# Check storage
kubectl get pvc -n keycloak
kubectl describe pvc sso-storage-pvc -n keycloak

# Check node disk space
ssh deploy@192.168.168.42 "df -h /mnt/nexus"
```

### Network Connectivity Issues

```bash
# Test pod-to-pod connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -n keycloak -- \
  wget -O- http://keycloak:8080/auth/health

# Check network policies
kubectl get networkpolicy -n keycloak

# Test service DNS
kubectl run -it --rm debug --image=busybox --restart=Never -n keycloak -- \
  nslookup keycloak.keycloak.svc.cluster.local
```

### PostgreSQL Replication Lag

```bash
# Check replication status
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres-secret -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# If lag > 1 second:
# 1. Check network bandwidth: kubectl top nodes
# 2. Check replica disk I/O: ssh deploy@192.168.168.42 "iostat -x"
# 3. Increase max_wal_senders if needed
```

### Auto-Deployment Not Triggering

```bash
# Check systemd service status
sudo systemctl status nexusshield-sso-deploy.service

# Check service logs
sudo journalctl -u nexusshield-sso-deploy.service -n 50

# Manually trigger deployment
ssh deploy@192.168.168.42 /opt/nexusshield/sso/scripts/sso-auto-deploy.sh

# Enable service (if disabled)
sudo systemctl enable nexusshield-sso-deploy.service
sudo systemctl start nexusshield-sso-deploy.service
```

---

## Git Workflow

### Local Development

```bash
# Create feature branch
git checkout -b feature/sso-enhancement

# Make changes
# ... edit files ...

# Commit
git commit -am "feat: SSO enhancement"

# Push to feature branch
git push origin feature/sso-enhancement
```

### Deployment to On-Premises

```bash
# After PR approval/merge to main:
git checkout main
git pull origin main

# Trigger deployment (automatic via systemd service)
# OR manual deployment:
./scripts/sso/sso-idempotent-deploy.sh
```

### Immediate Deployment (Direct to Main)

```bash
# For tested, approved changes:
git commit -am "feat: SSO fix"

# Direct merge to main (no PR needed, approved by user)
git push origin main

# Auto-deployment triggered automatically
# Verify: tail -f /mnt/nexus/audit/sso-audit-trail.jsonl
```

---

## Success Criteria

After deployment, verify:

- ✅ All pods running: `kubectl get pods -n keycloak`
- ✅ Storage mounted: `ls -la /mnt/nexus/sso-data`
- ✅ Audit trail created: `wc -l /mnt/nexus/audit/sso-audit-trail.jsonl`
- ✅ Keycloak accessible: `curl http://192.168.168.42:8080/auth/health`
- ✅ OAuth2-Proxy ready: `curl http://192.168.168.42:5000/api/v1/health`
- ✅ Grafana accessible: `curl http://192.168.168.42:3000/api/health`
- ✅ Tests passing: `./scripts/testing/integration-tests.sh`
- ✅ Auto-deployment working: `git push && wait 5min && kubectl get pods`

---

## Support & Escalation

### Daily Monitoring
- Check pod status: `kubectl get pods -n keycloak`
- Review dashboards: Grafana port-forward
- Monitor SLOs: Prometheus queries

### Weekly Maintenance
- Verify backups: `ls -la /mnt/nexus/backups/sso/`
- Check storage: `df -h /mnt/nexus`
- Review auth logs: `grep "auth_failure" /mnt/nexus/audit/sso-audit-trail.jsonl`

### Issues & Escalation
- Critical (P0): ops@nexus.local, senior-sre@nexus.local
- High (P1): ops@nexus.local
- Medium (P2): ops@nexus.local (during business hours)

---

## Documentation References

- **Complete Deployment Guide**: This file (SSO_ONPREM_DEPLOYMENT.md)
- **TIER 1 Implementation**: docs/SSO_TIER1_IMPLEMENTATION.md
- **TIER 2 Observability**: docs/SSO_TIER2_OBSERVABILITY.md
- **Operations Guide**: docs/SSO_COMPLETE_OPERATIONS_GUIDE.md
- **Integration Tests**: scripts/testing/integration-tests.sh
- **Client SDKs**: examples/ (JavaScript, Python, Go)

---

**Status**: 🟢 **PRODUCTION READY FOR ON-PREMISES DEPLOYMENT**  
**Target**: 192.168.168.42 (Worker Node)  
**Model**: Immutable | Ephemeral | Idempotent | Zero Cloud  
**Last Updated**: March 14, 2026  
**Version**: 1.0.0
