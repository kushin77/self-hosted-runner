# NFS Integration Guide for Dev Node

**Last Updated**: 2026-03-14  
**Status**: Ready for deployment  
**Scope**: Development node (192.168.168.31) ↔ NAS server (192.168.168.100)

---

## Executive Summary

This guide provides step-by-step instructions for deploying NFS mounts on the development node to access centralized repositories, configuration vaults, and audit logs. All processes enforce the mandatory best practices documented in [NAS_BEST_PRACTICES_MANDATES.md](NAS_BEST_PRACTICES_MANDATES.md).

**Key Outcomes:**
- ✅ Read-write access to centralized IAC repositories
- ✅ Read-only access to configuration vaults and audit trails
- ✅ Automatic health monitoring and stale mount recovery
- ✅ Persistent mounting across reboots
- ✅ Security hardening (root_squash, IP restrictions, firewall)

---

## Prerequisites Checklist

**Before deployment, verify:**

- [ ] NAS server (192.168.168.100) is reachable
  ```bash
  ping -c 3 192.168.168.100
  ```

- [ ] Network isolation confirmed (192.168.168.0/24)
  ```bash
  ip route show | grep 192.168.168
  ```

- [ ] NFS utilities installed on dev node
  ```bash
  which mountpoint && which showmount
  ```

- [ ] Root or sudo access available on dev node
  ```bash
  sudo whoami  # Must return "root"
  ```

- [ ] Firewall allows TCP port 2049
  ```bash
  sudo sysctl net.ipv4.tcp_established_connections | grep 2049  # site-specific verification
  ```

---

## Deployment Phase 1: NAS Admin Setup

**Prerequisite**: Coordinate with NAS administrator

### Step 1: Request Export Configuration

The NAS administrator must configure `/etc/exports` on the NAS server (192.168.168.100) with the following entries:

```bash
# Repositories (read-write for dev node only)
/nas/repositories  192.168.168.31(rw,root_squash,sync,no_subtree_check) \
                   192.168.168.42(ro,root_squash,sync,no_subtree_check)

# Configuration vault (read-only for both)
/nas/config-vault  192.168.168.31(ro,root_squash,sync,no_subtree_check) \
                   192.168.168.42(ro,root_squash,sync,no_subtree_check)

# Audit logs (read-only, append-only for authorized users)
/nas/audit-logs    192.168.168.31(ro,root_squash,sync,no_subtree_check) \
                   192.168.168.42(ro,root_squash,sync,no_subtree_check)
```

**Explanation:**
- `rw` = read-write (repositories only on dev node)
- `ro` = read-only (forced for config-vault, audit-logs)
- `root_squash` = map root to nobody (security hardening)
- `sync` = synchronous writes (data durability)
- `no_subtree_check` = skip subtree verification (performance)

### Step 2: Verify Exports on NAS

NAS administrator should execute:

```bash
# On NAS server (192.168.168.100)
sudo exportfs -a
sudo exportfs -v
```

Expected output shows all three exports with correct permissions and IP restrictions.

---

## Deployment Phase 2: Dev Node Setup

### Automated Setup (Recommended)

Run the complete dev node setup with integrated NFS mounting:

```bash
cd /home/akushnir/self-hosted-runner
sudo bash scripts/nas-integration/setup-dev-node.sh
```

This orchestrates:
1. ✅ Service account creation (automation user)
2. ✅ SSH key generation (for NAS push operations)
3. ✅ Script installation
4. ✅ Environment configuration
5. ✅ IAC directory structure
6. ✅ **NFS mount setup** (using setup-nfs-mounts.sh)
7. ✅ Systemd services + timers
8. ✅ Quick start guide

**Expected Duration:** 2-3 minutes  
**Est. Output Logs:** 30-40 lines with SUCCESS markers

### Manual NFS-Only Setup

If you prefer to run NFS setup independently:

```bash
cd /home/akushnir/self-hosted-runner
sudo bash scripts/nas-integration/setup-nfs-mounts.sh mount
```

Verify mounts are active:

```bash
bash scripts/nas-integration/setup-nfs-mounts.sh status
```

---

## Deployment Phase 3: Verification

### Quick Verification

```bash
# 1. Check mount points exist
ls -la /mnt/nas/

# 2. Verify NFS mounts are active
df -h | grep -E "repositories|config-vault|audit-logs"

# 3. Test repository access (should be readable + writable)
touch /mnt/nas/repositories/.read-write-test && rm /mnt/nas/repositories/.read-write-test && echo "✅ Repositories RW"

# 4. Test config vault (read-only)
ls -la /mnt/nas/config-vault/ && echo "✅ Config vault RO"

# 5. Test audit logs (read-only)
ls -la /mnt/nas/audit-logs/ && echo "✅ Audit logs RO"
```

### Comprehensive Validation Checklist

Run the validation script:

```bash
bash scripts/nas-integration/validate-nfs-mounts.sh --verbose
```

This checks:
- ✅ All mounts are responsive (no hangs)
- ✅ NFS client processes are running
- ✅ NAS server connectivity
- ✅ fstab entries are persistent
- ✅ Permissions match mandates
- ✅ Disk space is adequate

### Test Persistent Mounting

Simulate a reboot (no actual reboot needed):

```bash
# 1. Unmount and remount
sudo umount /mnt/nas/repositories /mnt/nas/config-vault /mnt/nas/audit-logs

# 2. Verify fstab remounts them
sudo mount -a

# 3. Confirm all are back
df -h | grep -E "repositories|config-vault|audit-logs"
```

---

## Operations & Monitoring

### Health Check Automation

The system automatically runs health checks every 30 minutes via systemd timer:

```bash
# View health check service
systemctl status nas-validate-health.service

# View health check timer
systemctl status nas-validate-health.timer

# View health check logs
journalctl -u nas-validate-health.service -n 20 -f
```

### Manual Health Checks

```bash
# Quick health check
bash scripts/nas-integration/validate-nfs-mounts.sh --quick

# Detailed health check
bash scripts/nas-integration/validate-nfs-mounts.sh --verbose

# Auto-repair (fix stale mounts)
sudo bash scripts/nas-integration/validate-nfs-mounts.sh --repair
```

### Handling Stale Mounts

If a mount becomes unresponsive (common in enterprise networks):

```bash
# Option 1: Automatic repair (preferred)
sudo bash scripts/nas-integration/validate-nfs-mounts.sh --repair

# Option 2: Manual recovery
# Step 1: Force unmount
sudo umount -l -f /mnt/nas/repositories

# Step 2: Remount via fstab
sudo mount -a

# Step 3: Verify recovery
df -h | grep repositories
```

---

## Data Flow & Timeline

### Synchronization Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Development Node (192.168.168.31)                       │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ /opt/iac-configs/  ← Developer edits here           │ │
│ └─────────────────────────────────────────────────────┘ │
│                          │                               │
│                          │ rsync (manual or watch)       │
│                          ▼                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ /mnt/nas/repositories  (NFS v4.1, RW via TCP)      │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
                            │ NAS serves as canonical source
                            │
┌─────────────────────────────────────────────────────────┐
│ NAS Server (192.168.168.100)                            │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ /nas/repositories (canonical)                       │ │
│ │ /nas/config-vault (read-only)                       │ │
│ │ /nas/audit-logs (immutable)                         │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                            │
                            │ Worker pulls periodically (30 min)
                            │
┌─────────────────────────────────────────────────────────┐
│ Worker Node (192.168.168.42)                            │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ /opt/deployed-configs/ (synced from NAS)            │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Timeline: Edit → Deploy

| Phase | Duration | Activity | Responsible |
|-------|----------|----------|-------------|
| **1** | 0-5 min  | Dev edits `/opt/iac-configs/` on dev node | Developer |
| **2** | 5 min    | Manual push via `dev-node-automation.sh push` | Automation service |
| **3** | 5-35 min | NAS holds canonical copy; worker pulls via timer | NAS + Worker |
| **4** | 35-40 min | Worker applies configuration | Deployment system |
| **TOTAL** | **40 min** | Change visible in production | System |

---

## Best Practices Reference

### Mandatory Constraints (Enforcement)

All NFS deployments must comply with constraints in [NAS_BEST_PRACTICES_MANDATES.md](NAS_BEST_PRACTICES_MANDATES.md):

- ✅ **NFS v4.1 only** - enforced at mount time
- ✅ **TCP protocol** - never UDP (reliability)
- ✅ **Hard mounts** - never soft (prevents silent data loss)
- ✅ **1MB block sizes** - for LAN optimization
- ✅ **Persistent via fstab** - survives reboots
- ✅ **root_squash on exports** - security hardening
- ✅ **IP-restricted exports** - network isolation
- ✅ **Health checks every 15 min** - operational visibility

### Performance Tuning

Mount options for production optimization:

```bash
# In /etc/fstab (already configured by setup script):
192.168.168.100:/nas/repositories  /mnt/nas/repositories  nfs4  \
  rsize=1048576,wsize=1048576,  \
  timeo=30,retrans=3,            \
  hard,bg,nointr,               \
  _netdev  0 0
```

**Explanation:**
- `rsize=1048576` = 1MB read block (max LAN throughput)
- `wsize=1048576` = 1MB write block
- `timeo=30` = 3-second timeout (reasonable for LAN)
- `retrans=3` = retry 3 times before giving up
- `hard` = hang on failure (never lose data silently)
- `bg` = retry mounts in background (non-blocking boot)
- `nointr` = mount cannot be interrupted (prevents partial unmounts)
- `_netdev` = network-dependent mount (waits for network)

---

## Troubleshooting

### Issue 1: "mount.nfs4: Connection refused"

**Diagnosis:**
```bash
# Check NAS connectivity
ping 192.168.168.100

# Verify NAS exports
showmount -e 192.168.168.100
```

**Resolution:**
1. Ensure NAS server exports are configured (Phase 1)
2. Confirm firewall allows TCP port 2049
3. Verify network isolation (check routing)

### Issue 2: "Stale NFS file handle"

**Diagnosis:**
```bash
# Mount appears active but unresponsive
df -h /mnt/nas/repositories  # May hang
ls /mnt/nas/repositories     # May hang or error
```

**Resolution:**
```bash
# Trigger automatic recovery
sudo bash scripts/nas-integration/validate-nfs-mounts.sh --repair

# Or manual recovery
sudo umount -l -f /mnt/nas/repositories && sudo mount -a
```

### Issue 3: "Read-only file system"

**Diagnosis:**
```bash
# Trying to write to a read-only mount
touch /mnt/nas/config-vault/test  # Permission denied
```

**Resolution:**
- This is **intentional** for config-vault and audit-logs
- Only repositories (`/mnt/nas/repositories`) are read-write
- Dev edits go to `/opt/iac-configs/`, then pushed to NAS

### Issue 4: "Mount point not found"

**Diagnosis:**
```bash
# /mnt/nas/ doesn't exist
ls /mnt/  # Empty or no 'nas'
```

**Resolution:**
```bash
# Run NFS setup to create mount points
sudo bash scripts/nas-integration/setup-nfs-mounts.sh mount
```

### Issue 5: "NFS processes not running"

**Diagnosis:**
```bash
# NFS client can't communicate
ps aux | grep nfs
```

**Resolution:**
```bash
# Re-initialize NFS client
sudo sysctl -p  # Reload kernel params
sudo systemctl restart nfs-client.target
sudo bash scripts/nas-integration/setup-nfs-mounts.sh mount
```

---

## Security Hardening Summary

### Network Isolation
- Dedicated 192.168.168.0/24 subnet
- Firewall rules restrict NFS (port 2049) to this subnet only
- No external access to NAS exports

### Export Permissions
- `root_squash` on all exports (maps root → nobody)
- `no_subtree_check` for performance (OK inside isolated subnet)
- IP-restricted exports (dev node + worker node only)

### Mount Permissions
```bash
# Repositories: 755 (writable by automation user)
ls -ld /mnt/nas/repositories   # drwxr-xr-x

# Config vault: 700 (readable by automation user only)
ls -ld /mnt/nas/config-vault   # drwx------

# Audit logs: 755 (append-only for audit system)
ls -ld /mnt/nas/audit-logs     # drwxr-xr-x
```

### Data Flow Protection
- All edits tracked in `/opt/iac-configs/` (local)
- All pushes logged with timestamps and checksums
- Audit log writes are append-only (immutable)
- Configuration snapshots stored separately

---

## Next Steps

### Immediate (Today)
1. [ ] Review [NAS_BEST_PRACTICES_MANDATES.md](NAS_BEST_PRACTICES_MANDATES.md)
2. [ ] Coordinate with NAS admin for export configuration (Phase 1)
3. [ ] Deploy dev node setup: `sudo bash setup-dev-node.sh`

### Short-term (This Week)
1. [ ] Verify mounts with validation script
2. [ ] Test IAC repository push/pull workflow
3. [ ] Confirm worker node receives updates
4. [ ] Review health check logs

### Medium-term (This Month)
1. [ ] Integrate monitoring with Prometheus/Grafana
2. [ ] Set up alerting for NFS mount failures
3. [ ] Document site-specific firewall rules
4. [ ] Create runbooks for common troubleshooting scenarios

### Long-term (Ongoing)
1. [ ] Monitor NFS performance metrics
2. [ ] Review audit logs weekly
3. [ ] Update best practices as infrastructure evolves
4. [ ] Scale to additional worker nodes as needed

---

## Reference Documentation

| Document | Purpose | Audience |
|----------|---------|----------|
| [NAS_BEST_PRACTICES_MANDATES.md](NAS_BEST_PRACTICES_MANDATES.md) | Mandatory constraints & enforcement | Ops/Security |
| [DEV_NODE_SETUP.md](DEV_NODE_SETUP.md) | Comprehensive reference (600+ lines) | DevOps Engineers |
| [DEV_NODE_NAS_INTEGRATION_SUMMARY.md](DEV_NODE_NAS_INTEGRATION_SUMMARY.md) | Quick start (10 min read) | All Teams |
| [DEV_NODE_NAS_INDEX.md](DEV_NODE_NAS_INDEX.md) | Navigation guide & FAQ | New Users |

---

## Support & Escalation

### Quick Reference Commands

```bash
# Status check (shows everything)
bash scripts/nas-integration/dev-node-automation.sh status

# Health monitoring
bash scripts/nas-integration/validate-nfs-mounts.sh --verbose

# Connectivity testing
bash scripts/nas-integration/dev-node-automation.sh connectivity

# Documentation
bash scripts/nas-integration/dev-node-automation.sh docs
```

### Escalation Path

| Issue | First Response | Escalate If |
|-------|----------------|-------------|
| Mount unresponsive | Run `--repair` | Persists after 3 attempts |
| NAS unreachable | Check ping + firewall | Network can't reach NAS |
| Permission denied | Verify mount type (RW vs RO) | Exports misconfigured |
| Performance slow | Review network | Consistent latency > 500ms |

---

**Document Version:** 1.0  
**Last Reviewed:** 2026-03-14  
**Next Review:** 2026-04-14  
**Owner:** Infrastructure Team  
**Status:** Production Ready
