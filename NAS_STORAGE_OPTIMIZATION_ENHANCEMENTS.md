# NAS Storage Optimization Strategy
## Full On-Premises Infrastructure Enhancement

**Date**: March 14, 2026  
**Status**: 🟢 Recommended Enhancement Plan  
**Target**: Maximize NAS (.100) utilization while keeping local drives for OS only

---

## Executive Summary

This enhancement strategy transforms your infrastructure into a **tiered storage architecture** where:
- **Local Drives**: OS only (immutable, ~50GB)
- **NAS (Shared Storage)**: Everything else - configs, databases, caches, logs, artifacts
- **Benefits**: Reduced local disk footprint, easier node replacement, centralized backup, improved cost efficiency

---

## Current State vs. Target State

### Current Architecture
```
Worker Node (.42)                    NAS (.100)
├─ OS (local SSD)                    ├─ IAC (/repositories)
├─ Docker images (local)             ├─ Configs (/config-vault)
├─ Application data (local)    ←────  ├─ Service creds (GSM sync)
├─ Database (local or remote)        └─ Audit logs
├─ Logs (local)
└─ Artifacts (local)
```

### Target Architecture (Proposed)
```
Worker Node (.42)                    NAS (.100)
├─ OS (local SSD, 50GB)      ✅      ├─ IAC (/repositories)
│  └─ Immutable, no changes  ✅      ├─ Configs (/config-vault)
│                            ✅      ├─ Service Creds (/secrets)
└─ NAS mount at /data        ←────   ├─ Logs (/logs/workers)
   └─ Symlinks to:                   ├─ Databases (/databases)
      ├─ /data/docker (images)       ├─ Container Cache (/cache)
      ├─ /data/postgres             ├─ Artifacts (/artifacts)
      ├─ /data/redis                ├─ Monitoring (/metrics)
      ├─ /data/elasticsearch        └─ Backups (/backups)
      ├─ /data/logs
      ├─ /data/artifacts
      └─ /data/metrics
```

---

## Enhancement 1: NFS Mounts for Persistent Storage

### Directory Structure on NAS

Create organized volumes on NAS:

```
/mnt/nas-storage/
├── databases/                    # 500GB - PostgreSQL, MongoDB
│   ├── postgresql/
│   ├── redis/
│   └── mongodb/
├── cache/                        # 100GB - Docker layer cache, npm cache
│   ├── docker-layers/
│   ├── npm-cache/
│   └── apt-cache/
├── logs/                         # 200GB - Application & system logs
│   ├── worker-42/
│   ├── worker-39/
│   ├── nginx/
│   └── kubernetes/
├── artifacts/                    # 300GB - Build artifacts, releases
│   ├── builds/
│   ├── releases/
│   └── exports/
├── metrics/                      # 50GB - Prometheus, historical data
│   ├── prometheus/
│   └── grafana/
├── backups/                      # 200GB - Weekly snapshots
│   ├── postgresql/
│   ├── configs/
│   └── volumes/
├── docker-images/               # 150GB - Cached Docker images
└── elasticsearch/               # 100GB - ElasticSearch data
```

### Worker Node Setup

**File**: `scripts/nas-storage/setup-nfs-mounts.sh`

```bash
#!/bin/bash
# Configure NFS mounts on worker nodes for persistent storage

set -euo pipefail

NAS_HOST="192.168.168.39"
NAS_EXPORT="/export/storage"

# 1. Mount NAS storage
echo "[*] Mounting NAS storage..."
sudo mkdir -p /data
sudo mount -t nfs -o rw,hard,intr,nolock "${NAS_HOST}:${NAS_EXPORT}" /data

# 2. Create symlinks for standard locations
echo "[*] Creating symlinks to NAS mounts..."
for dir in databases cache logs artifacts metrics docker elasticsearch; do
    sudo mkdir -p /data/$dir
    sudo chown root:root /data/$dir
done

# 3. Link application directories
sudo mkdir -p /var/lib/postgresql
sudo rm -rf /var/lib/postgresql  # Remove if local copy exists
sudo ln -s /data/databases/postgresql /var/lib/postgresql

sudo mkdir -p /var/lib/redis
sudo ln -s /data/databases/redis /var/lib/redis

sudo mkdir -p /var/log/application
sudo ln -s /data/logs/worker-$(hostname) /var/log/application

# 4. Docker layers cache
sudo mkdir -p /var/lib/docker
sudo ln -s /data/cache/docker-layers /var/lib/docker/overlay2

# 5. Set permissions
sudo chmod 755 /data
find /data -type d -exec sudo chmod 755 {} \;

# 6. Verify mounts
df -h /data
mount | grep nfs

echo "✅ NFS mounts configured successfully"
```

### NAS Server Configuration

**On NAS (.100)**: Export storage via NFS

```bash
# /etc/exports - Add these lines
/export/storage       192.168.168.0/24(rw,sync,no_subtree_check,no_root_squash)

# Apply exports
sudo exportfs -ra

# Verify
exportfs -v
showmount -e localhost
```

---

## Enhancement 2: Centralized Database on NAS

### PostgreSQL on NAS Storage

**File**: `scripts/nas-storage/postgres-to-nas.sh`

```bash
#!/bin/bash
# Migrate PostgreSQL data to NAS shared storage

set -euo pipefail

NAS_DB_PATH="/data/databases/postgresql"

# 1. Stop PostgreSQL
sudo systemctl stop postgresql

# 2. Move existing data (if any)
if [[ -d /var/lib/postgresql/14/main ]]; then
    sudo rsync -av /var/lib/postgresql/14/main/ "${NAS_DB_PATH}/" --delete
fi

# 3. Configure PostgreSQL for NAS storage
sudo tee /etc/postgresql/14/main/postgresql.conf > /dev/null << EOF
# PostgreSQL configuration for NAS storage
data_directory = '/data/databases/postgresql'
listen_addresses = '*'
shared_buffers = 256MB
effective_cache_size = 512MB
maintenance_work_mem = 64MB
synchronous_commit = 'on'
log_destination = 'stderr'
logging_collector = on
log_directory = '/data/logs/postgresql'
EOF

# 4. Fix permissions (NAS may have different ownership)
sudo chown -R postgres:postgres "${NAS_DB_PATH}"
sudo chmod 700 "${NAS_DB_PATH}"

# 5. Start PostgreSQL
sudo systemctl start postgresql

# 6. Verify
sudo -u postgres psql -c "SELECT version();"

echo "✅ PostgreSQL migrated to NAS storage"
```

Benefits:
- ✅ Centralized backup (single snapshot of all worker databases)
- ✅ Shared across all worker nodes if needed
- ✅ Easy disaster recovery
- ✅ Reduces local disk I/O contention

---

## Enhancement 3: Container & Image Caching on NAS

### Docker Layer Cache Optimization

**File**: `scripts/nas-storage/docker-cache-nas.sh`

```bash
#!/bin/bash
# Configure Docker to use NAS for layer caching

set -euo pipefail

NAS_DOCKER_CACHE="/data/cache/docker-layers"
NAS_IMAGES="/data/docker-images"

# 1. Create NAS directories
sudo mkdir -p "${NAS_DOCKER_CACHE}"
sudo mkdir -p "${NAS_IMAGES}"
sudo chmod 755 "${NAS_DOCKER_CACHE}" "${NAS_IMAGES}"

# 2. Stop Docker
sudo systemctl stop docker

# 3. Configure Docker daemon for NAS storage
sudo tee /etc/docker/daemon.json > /dev/null << 'EOF'
{
  "data-root": "/data/docker",
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "graph": "/data/docker",
  "insecure-registries": ["192.168.168.100:5000"],
  "registry-mirrors": ["http://192.168.168.100:5000"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3",
    "labels": "node=worker-42"
  }
}
EOF

# 4. Start Docker (it will re-initialize with NAS)
sudo systemctl start docker

# 5. Verify
docker info | grep "Docker Root Dir"
docker images

echo "✅ Docker configured to use NAS for image storage"
```

Benefits:
- ✅ Shared image layer cache between nodes (~60% storage savings)
- ✅ Faster deployments (reuse layers vs. re-download)
- ✅ Private registry on NAS (.100) as fallback mirror
- ✅ Survivable node loss (images persist on NAS)

### Local Registry Caching

**On NAS**: Host Docker registry mirror

```bash
# docker-compose on NAS (.100)
version: '3.8'
services:
  registry:
    image: registry:2
    ports:
      - "5000:5000"
    volumes:
      - /data/docker-images:/var/lib/registry
    environment:
      REGISTRY_LOG_LEVEL: info

  registry-mirror:
    image: registry:2
    ports:
      - "5001:5000"
    environment:
      REGISTRY_LOG_LEVEL: info
      REGISTRY_PROXY_REMOTEURL: https://registry.hub.docker.com
    volumes:
      - /data/docker-images/mirror:/var/lib/registry
```

---

## Enhancement 4: Centralized Application Logging

### Structured Logging to NAS

**File**: `scripts/nas-storage/logging-aggregation.sh`

```bash
#!/bin/bash
# Configure centralized logging to NAS

set -euo pipefail

NAS_LOG_PATH="/data/logs/$(hostname)"
WORKER_HOSTNAME="$(hostname)"

# 1. Create worker-specific log directory
sudo mkdir -p "${NAS_LOG_PATH}"
sudo chmod 755 "${NAS_LOG_PATH}"

# 2. Configure systemd journal to NAS
sudo tee /etc/systemd/journald.conf > /dev/null << EOF
[Journal]
Storage=persistent
Compress=yes
LogNamespace=system
ForwardToSyslog=no
MaxRetentionSec=30day
SystemMaxUse=10G
RuntimeMaxUse=256M
EOF

# 3. Forward logs to NAS
sudo tee /etc/rsyslog.d/99-nas-logging.conf > /dev/null << EOF
# Send all logs to NAS aggregation
*.* @@192.168.168.100:514

# Also keep local copy for immediate access
*.* -${NAS_LOG_PATH}/syslog

EOF

# 4. Configure application logging
sudo mkdir -p /data/logs/kubernetes
sudo mkdir -p /data/logs/docker
sudo mkdir -p /data/logs/application

# 5. Kubernetes logs to NAS
cat << 'KEOF' | sudo tee /etc/kubernetes/kubelet-logrotate.conf
/data/logs/kubernetes/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        systemctl reload kubelet
    endscript
}
KEOF

# 6. Restart logging services
sudo systemctl restart rsyslog
sudo systemctl restart systemd-journald

echo "✅ Centralized logging to NAS configured"
```

Benefits:
- ✅ Single source for all logs (searchable from NAS)
- ✅ 30-day retention on NAS (vs. local disk pressure)
- ✅ ElasticSearch on NAS can index everything
- ✅ Easier debugging and audit trail

### Log Rotation & Retention

**Prometheus + Grafana on NAS for visualization**

```yaml
# /data/metrics/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'on-prem-prod'

scrape_configs:
  - job_name: 'worker-42'
    static_configs:
      - targets: ['192.168.168.42:9100']
        labels:
          node: 'worker-42'
  
  - job_name: 'kubernetes'
    kubernetes_sd_configs:
      - role: node
```

---

## Enhancement 5: Kubernetes Persistent Volumes Backed by NAS

### StorageClass for Dynamic Provisioning

**File**: `k8s/storage/nfs-provisioner.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-nas
provisioner: nfs.csi.k8s.io
parameters:
  server: 192.168.168.100
  share: /export/kubernetes-pv
reclaimPolicy: Retain
allowVolumeExpansion: true

---
# PersistentVolume for PostgreSQL
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-pv
spec:
  capacity:
    storage: 500Gi
  accessModes:
    - ReadWriteOnce
  nfs:
    server: 192.168.168.100
    path: "/data/databases/postgresql"
  persistentVolumeReclaimPolicy: Retain

---
# PersistentVolumeClaim in workload
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: postgres-pvc
spec:
  storageClassName: nfs-nas
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Gi
```

---

## Enhancement 6: Smart Tiering Strategy

### What Goes Where

| Component | Location | Reason |
|-----------|----------|--------|
| **OS Filesystem** | Local SSD (50GB) | Immutable, boot |
| **Container Runtime** | Local (50GB) | /var/lib/docker minimal footprint |
| **Docker Images** | NAS (150GB) | Shared cache, persistent |
| **PostgreSQL Data** | NAS (500GB) | Centralized, backup-friendly |
| **Redis Cache** | NAS (50GB) | Shared cluster state |
| **Application Logs** | NAS (200GB) | Aggregated, searchable |
| **Build Artifacts** | NAS (300GB) | Long-term storage |
| **Metrics/Monitoring** | NAS (50GB) | Historical data, analysis |
| **Container scratch** | Local tmpfs | Ephemeral, clean boots |

### Automated Tiering Script

**File**: `scripts/nas-storage/smart-tiering.sh`

```bash
#!/bin/bash
# Implement smart storage tiering between local and NAS

set -euo pipefail

# Thresholds
LOCAL_DISK_THRESHOLD=85      # Use NAS if local > 85%
NAS_HOT_PATH="/data"          # Hot NAS path
LOCAL_SCRATCH="/tmp/scratch"  # Local scratch (tmpfs)

# 1. Monitor local disk usage
check_local_disk() {
    local usage=$(df /var/lib/docker | tail -1 | awk '{print $5}' | sed 's/%//')
    if (( usage > LOCAL_DISK_THRESHOLD )); then
        echo "[⚠️] Local disk $usage% - triggering NAS tiering"
        return 1
    fi
    return 0
}

# 2. Auto-migrate to NAS if needed
auto_migrate_to_nas() {
    # Identify large local files not on NAS
    find /var/lib/docker -size +100M -type f | while read file; do
        dest_dir="/data/docker/$(dirname $file | sed 's|/var/lib/docker||')"
        mkdir -p "$dest_dir"
        rsync -av "$file" "$dest_dir/"
        rm "$file"
        ln -s "${dest_dir}/$(basename $file)" "$file"
    done
}

# 3. Clean up local cache periodically
cleanup_local_cache() {
    # Keep only 30 days of local logs
    find /var/log -type f -mtime +30 -exec rm {} \;
    
    # Clean old Docker layers
    docker system prune -f --filter "until=72h"
    
    # Clean npm cache
    npm cache clean --force 2>/dev/null || true
}

# Main
if ! check_local_disk; then
    auto_migrate_to_nas
fi

cleanup_local_cache

echo "✅ Smart tiering check complete"
```

---

## Enhancement 7: Disaster Recovery & Backups

### NAS Snapshot Strategy

**File**: `scripts/nas-storage/backup-strategy.sh`

```bash
#!/bin/bash
# Daily snapshot and backup to NAS

set -euo pipefail

NAS_BACKUP_PATH="/data/backups"
WORKER_NAME="$(hostname)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# 1. Daily PostgreSQL backup
backup_postgres() {
    local backup_file="${NAS_BACKUP_PATH}/postgresql/${WORKER_NAME}_${TIMESTAMP}.sql.gz"
    mkdir -p "${NAS_BACKUP_PATH}/postgresql"
    
    sudo -u postgres pg_dump -Fc --all | gzip > "$backup_file"
    
    echo "[✓] PostgreSQL backed up: $backup_file"
}

# 2. Configuration snapshot
backup_configs() {
    local backup_file="${NAS_BACKUP_PATH}/configs/${WORKER_NAME}_${TIMESTAMP}.tar.gz"
    mkdir -p "${NAS_BACKUP_PATH}/configs"
    
    tar czf "$backup_file" \
        /etc/kubernetes \
        /etc/docker \
        /opt/automation/scripts \
        /data/config-vault
    
    echo "[✓] Configs backed up: $backup_file"
}

# 3. Docker images backup (weekly, space-intensive)
backup_docker_images() {
    if [[ $(date +%u) -eq 0 ]]; then  # Sunday
        docker save $(docker images -q) | gzip > \
            "${NAS_BACKUP_PATH}/docker/$(hostname)_${TIMESTAMP}.tar.gz"
        echo "[✓] Docker images backed up"
    fi
}

# 4. Retention policy
cleanup_old_backups() {
    # Keep only 30 days of backups
    find "${NAS_BACKUP_PATH}" -mtime +30 -delete
    echo "[✓] Old backups cleaned up"
}

# Run all backups
backup_postgres
backup_configs
backup_docker_images
cleanup_old_backups

echo "✅ Backup cycle complete"
```

### Backup Schedule (Cron on each worker)

```bash
# /etc/cron.d/nas-backups
# Daily at 2 AM
0 2 * * * root /opt/automation/scripts/nas-storage/backup-strategy.sh >> /var/log/backups.log 2>&1

# Weekly integrity check (Sunday at 3 AM)
0 3 * * 0 root /opt/automation/scripts/nas-storage/verify-backups.sh >> /var/log/backup-verify.log 2>&1
```

---

## Enhancement 8: Performance Optimization

### NFS Tuning for Optimal Performance

**On NAS Server**:

```bash
# /etc/exports - NFS optimization
/export/storage 192.168.168.0/24(rw,sync,no_subtree_check,no_root_squash,\
    wdelay,insecure,subtree_check,secure_locks,acl,anonuid=65534,anongid=65534)

# Increase NFS server threads
sudo sysctl -w sunrpc.tcp_slot_table_entries=32
sudo sysctl -w sunrpc.udp_slot_table_entries=32
echo "sunrpc.tcp_slot_table_entries = 32" | sudo tee -a /etc/sysctl.conf
```

**On Worker Nodes**:

```bash
# /etc/fstab - NFS mount optimization
192.168.168.100:/export/storage /data nfs4 \
  rw,hard,intr,timeo=600,retrans=2,vers=4.1,\
  proto=tcp,port=2049,_netdev 0 0

# NFS client tuning
sudo sysctl -w sunrpc.tcp_slot_table_entries=32
sudo sysctl -w net.ipv4.tcp_keepalive_time=60
```

### Benchmarking

```bash
#!/bin/bash
# Measure NAS performance

# Sequential write test (10GB file)
dd if=/dev/zero of=/data/test-write.bin bs=1M count=10240
# Expected: 50-200 MB/s on gigabit

# Sequential read test
dd if=/data/test-write.bin of=/dev/null bs=1M
# Expected: 100-300 MB/s on gigabit

# Small file I/O test (metadata heavy)
for i in {1..10000}; do touch /data/test-$i; done
# Expected: < 100 ms per small file

# Cleanup
rm /data/test-*
```

---

## Enhancement 9: Monitoring & Observability

### Storage Metrics to Track

**File**: `scripts/nas-storage/storage-metrics.sh`

```bash
#!/bin/bash
# Export storage metrics for Prometheus

PORT=9999

cat << 'EOF' | python3
import socket
import os
import subprocess

HOST = '0.0.0.0'
PORT = int(os.environ.get('PORT', 9999))

def get_metrics():
    metrics = []
    
    # Local disk usage
    result = subprocess.run(['df', '-B1', '/'], capture_output=True, text=True)
    lines = result.stdout.strip().split('\n')
    if len(lines) > 1:
        parts = lines[1].split()
        total = int(parts[1])
        used = int(parts[2])
        available = int(parts[3])
        metrics.append(f'disk_total_bytes{{mount="/",device="local"}} {total}')
        metrics.append(f'disk_used_bytes{{mount="/",device="local"}} {used}')
        metrics.append(f'disk_available_bytes{{mount="/",device="local"}} {available}')
    
    # NAS usage
    result = subprocess.run(['df', '-B1', '/data'], capture_output=True, text=True)
    lines = result.stdout.strip().split('\n')
    if len(lines) > 1:
        parts = lines[1].split()
        total = int(parts[1])
        used = int(parts[2])
        available = int(parts[3])
        metrics.append(f'disk_total_bytes{{mount="/data",device="nfs"}} {total}')
        metrics.append(f'disk_used_bytes{{mount="/data",device="nfs"}} {used}')
        metrics.append(f'disk_available_bytes{{mount="/data",device="nfs"}} {available}')
    
    return '\n'.join(metrics)

# Serve metrics
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind((HOST, PORT))
sock.listen(1)

print(f"Metrics exporter listening on {HOST}:{PORT}")

while True:
    conn, addr = sock.accept()
    metrics = get_metrics()
    response = f"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n{metrics}"
    conn.sendall(response.encode())
    conn.close()
EOF
```

### Prometheus Alerting Rules

```yaml
# nas-storage-alerts.yml
groups:
  - name: nas_storage
    rules:
      - alert: NASStorageHighUsage
        expr: (node_filesystem_avail_bytes{mountpoint="/data"} / node_filesystem_size_bytes{mountpoint="/data"}) < 0.2
        for: 5m
        annotations:
          summary: "NAS storage > 80% used"

      - alert: LocalDiskHighUsage
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.2
        for: 5m
        annotations:
          summary: "Local disk > 80% used"

      - alert: NFSMountUnresponsive
        expr: up{job="nfs-exporter"} == 0
        for: 2m
        annotations:
          summary: "NAS NFS mount unreachable"

      - alert: NASBackupFailed
        expr: time() - backup_last_success_timestamp > 86400
        annotations:
          summary: "Daily backup to NAS failed"
```

---

## Enhancement 10: Implementation Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Setup NFS exports on NAS (.100)
- [ ] Deploy NFS mount script to worker nodes
- [ ] Verify mount stability for 24 hours
- [ ] Create initial directory structure

### Phase 2: Database Migration (Week 2)
- [ ] Backup existing PostgreSQL data
- [ ] Migrate PostgreSQL to NAS storage
- [ ] Test failover scenarios
- [ ] Verify backup integrity

### Phase 3: Container Optimization (Week 3)
- [ ] Reconfigure Docker to use NAS storage
- [ ] Setup Docker registry mirror on NAS
- [ ] Test image pull performance
- [ ] Measure storage savings

### Phase 4: Logging & Monitoring (Week 4)
- [ ] Configure centralized logging
- [ ] Deploy ElasticSearch on NAS
- [ ] Setup Grafana dashboards
- [ ] Historic metric storage on NAS

### Phase 5: Automation & DR (Week 5)
- [ ] Implement automated backups
- [ ] Test disaster recovery procedures
- [ ] Setup monitoring alerts
- [ ] Document runbooks

---

## Implementation Scripts Summary

| Script | Purpose | When |
|--------|---------|------|
| `setup-nfs-mounts.sh` | Configure NFS mounts | Phase 1 |
| `postgres-to-nas.sh` | Migrate PostgreSQL | Phase 2 |
| `docker-cache-nas.sh` | Docker optimization | Phase 3 |
| `logging-aggregation.sh` | Centralized logs | Phase 4 |
| `backup-strategy.sh` | Automated backups | Phase 5 |
| `smart-tiering.sh` | Disk usage optimization | Ongoing |
| `storage-metrics.sh` | Prometheus integration | Phase 4 |

---

## Estimated Storage Requirements

### NAS Total Capacity Needed: ~2TB for production

| Component | Size | Growth |
|-----------|------|--------|
| Databases (PostgreSQL + Redis) | 500GB | 5GB/month |
| Docker Images + Layers | 150GB | 10GB/month |
| Application Logs | 200GB | 20GB/month |
| Build Artifacts | 300GB | 30GB/month |
| Metrics & Monitoring | 100GB | 5GB/month |
| Backups (30 days) | 300GB | — |
| Configs & IAC | 50GB | 1GB/month |
| **Total** | **1.6TB** | **~70GB/month** |

### Local Disk (Worker Nodes): 100GB total

| Component | Size |
|-----------|------|
| OS + kernel | 30GB |
| Docker runtime (minimal) | 10GB |
| Container scratch/tmp | 30GB |
| Logs (24-hour local cache) | 20GB |
| **Total** | **100GB** |

---

## Key Benefits Summary

✅ **Scalability** - Add nodes without replicating storage  
✅ **Cost Efficiency** - Shared storage vs. per-node duplication  
✅ **Reliability** - Single point of backup and recovery  
✅ **Performance** - Optimized layer caching, smart tiering  
✅ **Maintainability** - Centralized configuration, easier troubleshooting  
✅ **Disaster Recovery** - Daily backups, easy recovery procedures  
✅ **Monitoring** - Unified observability across all nodes  
✅ **Flexibility** - Easy to add/remove worker nodes  

---

## Rollback Strategy

If issues arise, each phase can be rolled back:
1. Preserve backups before each phase
2. Keep local copies during transition
3. Use snapshots for quick reversion
4. Test all changes on staging first

---

## Next Steps

1. **Review** this enhancement plan with your team
2. **Prepare** NAS with expanded storage (2TB recommended)
3. **Implement** Phase 1 (NFS mounts) in staging environment
4. **Validate** for 1 week before rolling to production
5. **Execute** remaining phases per roadmap

---

## Support & Questions

For specific deployment details:
- NFS configuration: See `/data/docs/NAS_INTEGRATION_COMPLETE.md`
- PostgreSQL migration: See `postgres-to-nas.sh` implementation
- Docker optimization: See Docker documentation + our benchmarking results
- Monitoring setup: See Prometheus + Grafana configuration examples
