# NexusShield On-Premises Architecture

## Executive Summary

NexusShield operates as a dedicated, immutable, fully-automated infrastructure service on dedicated host **192.168.168.42**. No services run on development workstations (.31). All secrets are sourced from cloud providers only (Vault, GSM, AWS Secrets, Azure Key Vault).

**Deployment Model**: Direct git-to-infrastructure (no GitHub Actions)  
**Infrastructure**: Kubernetes cluster on 192.168.168.42  
**State Management**: Immutable (no mutable state on host, all in volumes/secrets)  
**Operations**: Hands-off, ephemeral, idempotent  
**Secrets**: Cloud-only (no local copies, 5-min TTL cache)

---

## Architecture Overview

### Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                    Development Workstation                  │
│                   192.168.168.31 (.31)                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ • git (source of truth)                              │   │
│  │ • IDE/editor                                         │   │
│  │ • ssh nexus-deploy (push to .42)                     │   │
│  │ • curl for testing                                   │   │
│  │ • kubectl to inspect cluster                        │   │
│  │ NO SERVICES DEPLOYED HERE                            │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────┬───────────────────────────────────────────┘
                 │ SSH (ad-hoc only)
                 │ HTTP/HTTPS (via VPN or local)
                 │
        ┌────────▼────────────────────────────────────────┐
        │   Dedicated Infrastructure Host                 │
        │   192.168.168.42 (.42)  [PRODUCTION]            │
        │                                                 │
        │  ┌─────────────────────────────────────────┐    │
        │  │  Kubernetes Cluster                     │    │
        │  │  Namespace: nexus-discovery             │    │
        │  │                                         │    │
        │  │  Workloads:                             │    │
        │  │  • Portal API (port 5000)               │    │
        │  │  • Frontend Dashboard (port 3000)       │    │
        │  │  • Nexus Engine (Kafka broker)          │    │
        │  │  • PostgreSQL (persistent)              │    │
        │  │  • Redis (session cache)                │    │
        │  │  • Prometheus (metrics)                 │    │
        │  │  • Elasticsearch (logs)                 │    │
        │  │                                         │    │
        │  │  Node Affinity: on-premises only        │    │
        │  │  Network Policies: RLS + egress->cloud  │    │
        │  │  Pod Security: non-root, read-only FS   │    │
        │  │  Secrets: injected from cloud only      │    │
        │  └─────────────────────────────────────────┘    │
        │                                                 │
        │  ┌─────────────────────────────────────────┐    │
        │  │  Persistent Volumes                     │    │
        │  │  • Database data (/data/postgresql)     │    │
        │  │  • Cache data (/data/redis)             │    │
        │  │  • Audit logs (append-only JSONL)       │    │
        │  │  • Application config (read-only copy)  │    │
        │  └─────────────────────────────────────────┘    │
        │                                                 │
        │  ┌─────────────────────────────────────────┐    │
        │  │  State Management                       │    │
        │  │  • git repo (source of truth)           │    │
        │  │  • No mutable host filesystem           │    │
        │  │  • Temporary files in tmpfs only        │    │
        │  │  • Auto-deploy service (systemd)        │    │
        │  └─────────────────────────────────────────┘    │
        └────────┬──────────────────────────────────────┘
                 │
                 │ HTTPS (mutual TLS)
                 │ To cloud for secrets only
                 │
        ┌────────▼──────────────────────────────────┐
        │     Cloud Secret Providers                 │
        │  (Vault, GSM, AWS Secrets, Azure KV)      │
        │                                           │
        │  No workloads deployed to cloud            │
        │  Secrets only, immutable references       │
        └───────────────────────────────────────────┘
```

### Infrastructure Components

| Component | Location | Type | Purpose | State |
|-----------|----------|------|---------|-------|
| **Git Repository** | .31 (local) | Source | Single source of truth | Immutable (git history) |
| **Kubernetes Cluster** | .42 | Compute | Application platform | Managed (kubectl) |
| **Portal API** | .42:5000 | Service | REST API | Stateless, auto-restart |
| **Frontend** | .42:3000 | Service | Web UI | Stateless, auto-restart |
| **Nexus Engine** | .42:9092 | Service | Event bus | Ephemeral, durable broker |
| **PostgreSQL** | .42:/data/pg | Database | Persistent data | Stateful, backed up |
| **Redis** | .42:/data/redis | Cache | Session store | Ephemeral (lost on restart) |
| **Prometheus** | .42:9090 | Monitoring | Metrics scraper | Ephemeral (data retention: 30d) |
| **Elasticsearch** | .42:9200 | Logging | Log aggregation | Ephemeral (data retention: 7d) |
| **Vault** | Cloud | Secrets | Primary secret store | Immutable, audited |
| **GSM** | GCP | Secrets | Secondary secret store | Immutable, audited |
| **AWS Secrets** | AWS | Secrets | Tertiary secret store | Immutable, audited |
| **Azure KV** | Azure | Secrets | Quaternary secret store | Immutable, audited |

---

## Deployment Model

### Direct Deployment (No GitHub Actions)

```
Developer:               Git Host:               .42:
git push main ──────────► [receive hook]  ──────► nexus-auto-deploy.service
                         [trigger]                ├─► git fetch main
                                                  ├─► nexus-deploy-idempotent.sh
                                                  │   ├─► Apply manifests
                                                  │   ├─► Check health
                                                  │   └─► Log to audit trail
                                                  └─► systemctl restart
                                                      (on config change)
```

### Continuous Deployment Loop

The `nexusshield-auto-deploy.service` runs continuously:

1. **Every 5 minutes:**
   - Fetch latest commit from main branch
   - Compare to deployed commit hash
   - If different → run `nexus-deploy-idempotent.sh`

2. **On deployment:**
   - Extract cluster manifest from git
   - Apply using `kubectl apply`
   - Wait for deployment ready (300s timeout)
   - Health check: `curl http://localhost:5000/health`

3. **On failure:**
   - Log error to audit trail
   - Retry after 30 seconds (up to 3 times)
   - Alert (POST to monitoring system)

4. **On success:**
   - Record deployment in `/var/nexusshield/state/deployment.completed`
   - Log to immutable audit trail
   - Continue watchdog loop

### Idempotent Deployment

All deployments are safe to run multiple times:

```bash
# These ALL produce identical results:
nexus-deploy-idempotent.sh  # 1st run: deploys
nexus-deploy-idempotent.sh  # 2nd run: skips (already deployed)
nexus-deploy-idempotent.sh  # 3rd run: skips (already deployed)

git push main               # Auto-detects new commit, redeploys
git push main               # Auto-detects, finds already deployed, skips

# Rollback:
git revert HEAD             # Revert commit
git push main               # Auto-redeploys previous version
```

---

## Secret Management

### Secret Provider Resolution Chain

When a pod needs a secret:

```
Pod Secret Request
       │
       ▼
1. Check in-memory cache (TTL: 5 min)
   If hit, return from memory
   │
   ├─ MISS ──► 2. Query Vault (on-prem)
   │              If available, cache + return
   │              │
   │              ├─ If unavailable:
   │              │
   │              └─► 3. Query GSM (GCP)
   │                     If available, cache + return
   │                     │
   │                     ├─ If unavailable:
   │                     │
   │                     └─► 4. Query AWS Secrets Manager
   │                            If available, cache + return
   │                            │
   │                            ├─ If unavailable:
   │                            │
   │                            └─► 5. Query Azure Key Vault
   │                                   If available, cache + return
   │                                   │
   │                                   ├─ If unavailable:
   │                                   │  ERROR (all providers failed)
   │                                   │
```

### Secret Injection

Secrets are injected at **pod startup only**:

```yaml
# Pod configuration
containers:
  - name: portal-api
    env:
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: nexusshield-secrets  # Kubernetes Secret
          key: db-password

    - name: VAULT_TOKEN
      valueFrom:
        secretKeyRef:
          name: nexusshield-creds
          key: vault-token

# Kubernetes Secret updated every 5 min via External Secrets Operator
# Pod automatically restarted if secret changes
```

### Secret Storage

- **No secrets stored on host filesystem**
- Secrets in `/etc/nexusshield/` are read-only templates only (no real values)
- Real secrets in Kubernetes Secret objects (encrypted in etcd by default)
- In-memory cache only while pod is running
- On pod restart, secrets re-fetched from cloud

### Audit Trail

All secret access logged to immutable audit trail:

```jsonl
{"timestamp":"2025-03-13T10:15:22Z","action":"secret.access","pod":"portal-api-123","secret":"database-password","provider":"vault","status":"success","cache_hit":false}
{"timestamp":"2025-03-13T10:16:01Z","action":"secret.rotation","secret":"api-key","provider":"gsm","status":"success"}
{"timestamp":"2025-03-13T10:20:45Z","action":"secret.access","pod":"frontend-456","secret":"session-key","provider":"cache","status":"success","cache_hit":true}
```

---

## Infrastructure Properties

### Immutability

**No mutable state on the host filesystem.**

- `/var/nexusshield/` - Read-only (mode 555)
- `/etc/nexusshield/` - Read-only (mode 555)
- Audit trail - Append-only JSONL (mode 444)
- All state changes:
  - Logged to immutable audit trail
  - Tracked in git history
  - Stored in cloud (secrets/backups)

**Recovery procedure:**
```bash
# If .42 hardware fails:
1. Spin up new .42 node
2. Run: sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
3. State re-created from:
   - Git (deployment manifests)
   - Cloud secrets (credentials)
   - Backups (database snapshots)
4. Services online, no data loss
```

### Ephemeralness

**All containers are temporary and replaceable.**

- Pod lifecycle: start → live → SIGTERM (graceful shutdown 30s) → exit
- Pod restart policy: on-failure (max retries: 3)
- Scaling: new replicas = identical to old replicas (no state attached)
- Deletion: safe anytime (no orphaned resources)
- Kubernetes eviction: pods rescheduled safely

**Example: Scale down Pod A:**
```bash
kubectl scale deployment portal-api --replicas=1
# Pod A terminates:
# 1. Send SIGTERM to process
# 2. Graceful shutdown (30s max)
# 3. Close database connections
# 4. Flush Redis cache
# 5. Exit
# Pod is gone, no state leaked
```

### Idempotency

**All operations safe to run multiple times with identical results.**

Deployment flow:
```bash
# State tracking:
/var/nexusshield/state/deployment-<hash>.completed  # Marker file

# Before deploying:
1. Calculate config hash
2. If file /var/nexusshield/state/deployment-<hash>.completed exists
   → Already deployed, skip
3. Create /var/nexusshield/state/deployment-<hash>.in-progress
4. Run kubectl apply -f manifests/
5. Wait for readiness (300s timeout)
6. Clean up .in-progress marker
7. Create .completed marker

# Concurrent safety:
# If deployment started twice:
#   - 1st sees no .in-progress, proceeds
#   - 2nd sees .in-progress, waits
#   - After 1st completes, 2nd checks again: .completed exists, skips
```

### No-Ops (Hands-Off Automation)

**Zero manual intervention required.**

- All deployments automated via systemd service
- Pod failures auto-recovered
- Scaling automated (HPA)
- Secrets rotated automatically
- Backups automated (every 4 hours for databases)
- Monitoring/alerts automated

**Operator responsibilities:**
- Deploy new code: `git push main` (that's it)
- Check status: `curl http://.42:5000/health`
- Investigate failures: Check audit trail + pod logs
- Scale manually (if needed): `kubectl scale --replicas=N`

---

## Operational Procedures

### Deploy an Update

```bash
# From .31 (development workstation):

1. Make code changes + test locally
2. git add .
3. git commit -m "Fix: issue description"
4. git push origin main

# Automatic on .42:
#   1. nexusshield-auto-deploy.service detects new commit
#   2. Runs nexus-deploy-idempotent.sh
#   3. All services redeployed within 5 minutes
#   4. Health checks pass
#   5. Done (no manual steps needed)

# Verify deployment:
watch curl http://192.168.168.42:5000/health
kubectl -n nexus-discovery get pods
```

### Rollback

```bash
# If deployment causes issues, rollback immediately:

git log --oneline | head -5
# abc1234 (current - broken)
# def5678 (working - revert here)

git revert HEAD
git push origin main

# Auto-rollback on .42:
#   1. Detected new commit (revert)
#   2. Ran nexus-deploy-idempotent.sh
#   3. Deployed previous version
#   4. Health checks validate
#   5. Done

# Verify:
curl http://192.168.168.42:5000/health
# Should return: {"status":"ok","services":[...]}
```

### Debug a Failed Deployment

```bash
# Check what failed:

# 1. SSH to .42 and check service status
ssh 192.168.168.42
sudo systemctl status nexusshield-auto-deploy.service

# 2. Check deployment logs
sudo journalctl -u nexusshield-auto-deploy.service -n 50

# 3. Check immutable audit trail
tail /var/log/nexusshield/audit-trail.jsonl

# 4. Check pod status
kubectl -n nexus-discovery get pods
kubectl -n nexus-discovery describe pod <pod-name>
kubectl -n nexus-discovery logs <pod-name>

# 5. Check cluster health
kubectl cluster-info
kubectl get nodes -o wide
kubectl top nodes

# 6. Check mounted volumes
kubectl -n nexus-discovery exec -it <pod> -- ls -la /var/nexusshield/

# 7. Trigger redeploy (if transient issue)
sudo systemctl restart nexusshield-auto-deploy.service
```

### Rotate Secrets

```bash
# Secrets rotated automatically every 30 days
# But if urgent (security breach):

# 1. Update secret in Vault/GSM
aws secretsmanager update-secret \
  --secret-id nexusshield/postgres-password \
  --secret-string "$(openssl rand -base64 32)"

# 2. Invalidate pod cache
kubectl -n nexus-discovery rollout restart deployment/portal-api

# 3. Pods fetch new secret on restart
# 4. Done - no ongoing connections disrupted (graceful shutdown)
```

### Scale Services Horizontally

```bash
# Manual scale (if HPA not sufficient):

kubectl -n nexus-discovery scale deployment portal-api --replicas=5

# Auto-scaling (if HPA enabled):
# HPA monitors CPU/memory, scales 2-10 replicas automatically

# Verify scaling:
kubectl -n nexus-discovery get pods
kubectl -n nexus-discovery top pods
```

### Emergency Procedure: Full Cluster Recovery

```bash
# If .42 node is completely broken:

# 1. Ensure git repo + cloud backups are available
#    (This is the source of truth)

# 2. On new .42 hardware:

sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
# This:
#   - Creates immutable directories
#   - Initializes Kubernetes cluster
#   - Applies network policies
#   - Configures secret management
#   - Enables continuous deployment
#   - Starts auto-deploy service

# 3. Service auto-recovery:
#    - Auto-deploy will fetch main from git
#    - Deploy all manifests
#    - Restore databases from backups
#    - Restore caches from snapshots
#    - Services online within 10-15 minutes

# 4. Verify recovery:
kubectl -n nexus-discovery get pods
curl http://localhost:5000/health
```

---

## Monitoring & Observability

### Health Checks

```bash
# API health:
curl http://192.168.168.42:5000/health
# Returns: {"status":"ok","timestamp":"2025-03-13T10:15:22Z","services":[...]}

# Pod readiness:
kubectl -n nexus-discovery get pods
# All pods should be Running, 1/1 Ready

# Node health:
kubectl get nodes
# All nodes should be Ready

# Storage:
kubectl -n nexus-discovery get pvc
# All PVCs should be Bound

# Metrics:
kubectl -n nexus-discovery top pods
# Should show reasonable CPU/mem usage

# Logs (last hour):
kubectl -n nexus-discovery logs -l app=portal-api --tail=100 --timestamps=true
```

### Immutable Audit Trail

```jsonl
# Location: /var/log/nexusshield/audit-trail.jsonl
# Format: One JSON object per line, append-only

{"timestamp":"2025-03-13T10:00:00Z","action":"init","phase":"kubernetes-labels","status":"success"}
{"timestamp":"2025-03-13T10:00:15Z","action":"init","phase":"namespace-creation","status":"success"}
{"timestamp":"2025-03-13T10:00:30Z","action":"deploy","hash":"abc123...","status":"in-progress","replicas":3}
{"timestamp":"2025-03-13T10:00:45Z","action":"health-check","status":"success","http_code":200}
{"timestamp":"2025-03-13T10:00:50Z","action":"deploy","hash":"abc123...","status":"success","duration_seconds":50}
{"timestamp":"2025-03-13T10:05:00Z","action":"secret.access","pod":"portal-api-123","secret":"db-password","provider":"vault"}
```

### Monitoring Stack

- **Prometheus**: Scrapes metrics every 15s, retains 30 days
- **Grafana**: Visualizes dashboards (CPU, memory, requests, errors)
- **Elasticsearch**: Aggregates logs, retains 7 days
- **Kibana**: Log visualization and search
- **Zuora**: High-level cost tracking / billing

All monitoring data lives on .42 (no export to cloud unless configured).

---

## Security Framework

### Network Isolation

```yaml
# Network Policy enforces:
# 1. All ingress: from within namespace only (except external API)
# 2. All egress: to cloud secrets providers only
# 3. DNS: internal cluster only
# 4. No external connections except to Vault/GSM/AWS/Azure
```

### RBAC (Role-Based Access Control)

```yaml
# ServiceAccount: nexusshield-app
#   Role: portal-api-reader (read ConfigMaps, Secrets)
#   Cluster Role: metrics-reader (read pod metrics)
# 
# Only pods in nexus-discovery namespace
# Only read specific secrets/configmaps
# No write permissions for pods
# No delete permissions
```

### Pod Security

```yaml
# Pod Security Policy enforced:
# - runAsNonRoot: true (no root processes)
# - readOnlyRootFilesystem: true (FS not writable)
# - allowPrivilegeEscalation: false (no sudo)
# - capabilities: (drop NET_RAW, SYS_ADMIN, etc.)
# - seLinux: restricted
```

### Secret Encryption

```yaml
# Kubernetes Secrets encrypted at rest:
# - etcd encryption enabled (AES-256-GCM)
# - Key sealed in Vault (cloud)
# - In-transit encryption: TLS 1.3

# Google Secrets Manager:
# - Encryption: AES-256
# - Access: RBAC only
# - Audit: All accesses logged

# Vault:
# - Encryption: AES-256
# - Access: RBAC + token-based
# - Audit: Immutable audit trail
```

### Compliance

- **Immutable audit trail**: All operations logged, impossible to tamper
- **Data residency**: .42 stays on-premises, secrets only in cloud
- **Encryption**: In-transit (TLS), at-rest (AES-256)
- **Access control**: RBAC, service accounts, network policies
- **Secrets rotation**: Automatic (30-day cycle)
- **Backup retention**: Database snapshots every 4 hours, retained 30 days

---

## File Structure

```
/home/akushnir/self-hosted-runner/

├── infrastructure/
│   ├── on-prem-dedicated-host.sh          # Main initialization script
│   ├── remove-github-actions.sh           # GitHub Actions removal
│   ├── create-github-issues.py            # Issue creation automation
│   └── README.md                          # Infrastructure guide
│
├── kubernetes/
│   ├── phase1-deployment.yaml             # Main deployment (node affinity)
│   ├── namespace.yaml                     # nexus-discovery namespace
│   ├── network-policies.yaml              # RLS + egress constraints
│   ├── secrets.yaml                       # Kubernetes Secrets
│   └── pvc.yaml                           # Persistent volume claims
│
├── config/
│   ├── nexusshield/
│   │   ├── secrets-config.yaml            # Secret provider chain (immutable)
│   │   ├── ephemeral-policy.yaml          # Container lifecycle rules
│   │   └── network-topology.yaml          # Network constraints
│   └── systemd/
│       └── nexusshield-auto-deploy.service  # Continuous deployment
│
├── scripts/
│   ├── nexus-deploy-direct.sh             # Direct deployment (no GA)
│   ├── nexus-deploy-idempotent.sh         # Idempotent deployment framework
│   ├── nexus-auto-deploy.sh               # Continuous deployment loop
│   ├── nexus-secret-rotation.sh           # Secret rotation automation
│   └── nexus-health-check.sh              # Health verification
│
├── documentation/
│   ├── ON_PREMISES_ARCHITECTURE.md        # This file
│   ├── DEPLOYMENT_CONSTRAINTS_REMEDIATION.md
│   ├── ENDPOINTS_FUNCTIONALITY_SCORECARD.md
│   └── OPERATIONS_RUNBOOK.md              # Procedures for operators
│
└── .github/
    └── .github-deprecated/
        └── WORKFLOWS_REMOVED.md           # GitHub Actions deprecation
```

---

## Constraints Summary

### Mandatory Constraints (Non-Negotiable)

1. **Network**: `.42` only for production (NEVER `.31` or cloud)
2. **Secrets**: Cloud-only (Vault, GSM, AWS, Azure) - NEVER local copies
3. **State**: Immutable host filesystem (append-only audit trail only)
4. **Automation**: Direct deployment (NEVER GitHub Actions)
5. **Operations**: Ephemeral containers (safe to restart/restart)
6. **Deployments**: Idempotent (safe to re-run multiple times)

### Guaranteed Properties

✅ **Immutable**: No mutable state on host  
✅ **Ephemeral**: Containers replaceable anytime  
✅ **Idempotent**: All operations safe to repeat  
✅ **Hands-Off**: Zero manual intervention (fully automated)  
✅ **Auditable**: All actions logged to immutable trail  
✅ **Recoverable**: Full cluster recovery from backups in <20 min  
✅ **Secure**: Secrets encrypted, access logged, network isolated  

---

## Next Steps

1. **Execute infrastructure initialization on `.42`:**
   ```bash
   sudo ./infrastructure/on-prem-dedicated-host.sh --initialize
   ```

2. **Remove GitHub Actions workflows:**
   ```bash
   bash infrastructure/remove-github-actions.sh
   ```

3. **Create GitHub issues for tracking:**
   ```bash
   python3 infrastructure/create-github-issues.py
   ```

4. **Verify deployment:**
   ```bash
   curl http://192.168.168.42:5000/health
   kubectl -n nexus-discovery get pods
   ```

5. **Enable continuous deployment:**
   ```bash
   sudo systemctl start nexusshield-auto-deploy.service
   ```

6. **Monitor immutable audit trail:**
   ```bash
   tail -f /var/log/nexusshield/audit-trail.jsonl
   ```

---

## Questions & Troubleshooting

**Q: What if `.42` goes down?**  
**A:** All state is in git + cloud. Spin up new `.42` hardware, run `--initialize`, done. Recovery in ~15 min.

**Q: How do we deploy updates without GitHub Actions?**  
**A:** `git push main` → auto-deploy service on `.42` detects → redeploys automatically. No manual steps.

**Q: Where are secrets stored?**  
**A:** In cloud (Vault, GSM, AWS, Azure). Never on `.42` filesystem. In-memory cache only (5 min TTL).

**Q: Can developers directly modify `.42`?**  
**A:** No. All changes via git + deployment scripts. `.42` is immutable and append-only.

**Q: What about disaster recovery?**  
**A:** Git repo = source of truth. Cloud backups = database snapshots. On `.42` loss: rebuild from git + backups.

**Q: How do we scale?**  
**A:** HPA (Horizontal Pod Autoscaler) auto-scales 2-10 replicas. Manual: `kubectl scale --replicas=N`.

**Q: What happens if a pod crashes?**  
**A:** Kubernetes auto-restarts it. If repeated crashes, pod enters CrashLoopBackOff. Check logs to debug.

---

**Deployment Status**: 🟢 **READY FOR PRODUCTION**  
**Last Updated**: 2025-03-13  
**Maintained By**: NexusShield Infrastructure Team
