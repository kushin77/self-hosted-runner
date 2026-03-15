# ✨ NAS DIRECT DEPLOYMENT - IMMEDIATE ACTIONS

## Status: 🟢 READY FOR DEPLOYMENT

All orchestration scripts are prepared. Execute in two stages:

---

## 📌 STAGE 1: NAS Configuration (kushin77@192.168.168.39)

**What**: Configure NFS exports on the NAS  
**When**: Run immediately  
**Where**: On NAS host 192.168.168.39  
**User**: kushin77 (you are this user)  
**Time**: ~2 minutes

### Copy and Execute This Block:

```bash
#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         NAS EXPORT CONFIGURATION                            ║"
echo "║         Host: 192.168.168.39 (kushin77)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create directories
echo "Step 1: Creating export directories..."
sudo mkdir -p /export/{repositories,config-vault,audit-logs}
sudo chmod 755 /export /export/{repositories,config-vault,audit-logs}
echo "✓ Directories created"
echo ""

# Step 2: Backup
echo "Step 2: Backing up /etc/exports..."
BACKUP_FILE="/etc/exports.backup.$(date +%Y%m%d-%H%M%S)"
sudo cp /etc/exports "$BACKUP_FILE"
echo "✓ Backup: $BACKUP_FILE"
echo ""

# Step 3: Add NFS exports
echo "Step 3: Adding NFS export entries..."
sudo tee -a /etc/exports > /dev/null << 'EXPORTS'

# NFS Exports for Dev/Worker Nodes (Added 2026-03-15)
/export/repositories 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/repositories 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.42(ro,sync,no_subtree_check,root_squash)
EXPORTS
echo "✓ Entries added"
echo ""

# Step 4: Export shares
echo "Step 4: Exporting NFS shares..."
sudo exportfs -r
echo "✓ Exports reloaded"
echo ""

# Step 5: Verify
echo "Step 5: Verifying configuration..."
echo "Current NFS exports:"
sudo showmount -e localhost
echo ""
echo "✓ STAGE 1 COMPLETE"
```

### Verification (after Stage 1):
```bash
# Verify exports are accessible
sudo showmount -e localhost

# Should output:
# Export list for localhost:
# /export/repositories 192.168.168.31,192.168.168.42
# /export/config-vault 192.168.168.31,192.168.168.42
# /export/audit-logs 192.168.168.31,192.168.168.42
```

**✅ Once verified, proceed to Stage 2**

---

## 📌 STAGE 2: Dev Node Configuration (akushnir@192.168.168.31)

**What**: Mount NAS exports on dev node  
**When**: After Stage 1 verification  
**Where**: On dev node 192.168.168.31  
**User**: akushnir  
**Time**: ~3 minutes  

### Execute on Dev Node:

```bash
#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         DEV NODE NFS MOUNT SETUP                            ║"
echo "║         Host: 192.168.168.31 (akushnir)                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Create mount directories
echo "Step 1: Creating mount directories..."
sudo mkdir -p /mnt/nas/{repositories,config-vault,audit-logs}
echo "✓ Mount directories created"
echo ""

# Step 2: NFS mount options
echo "Step 2: Setting NFS mount options..."
NFS_OPTS_BASE="vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576"
NFS_OPTS_RW="${NFS_OPTS_BASE}"
NFS_OPTS_RO="${NFS_OPTS_BASE},ro"
echo "✓ Mount options configured"
echo ""

# Step 3: Mount repositories (RW)
echo "Step 3: Mounting repositories (RW)..."
if ! mountpoint -q /mnt/nas/repositories 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RW}" 192.168.168.39:/export/repositories /mnt/nas/repositories
  echo "✓ Repositories mounted"
else
  echo "ℹ Repositories already mounted"
fi
echo ""

# Step 4: Mount config-vault (RO)
echo "Step 4: Mounting config-vault (RO)..."
if ! mountpoint -q /mnt/nas/config-vault 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RO}" 192.168.168.39:/export/config-vault /mnt/nas/config-vault
  echo "✓ Config vault mounted"
else
  echo "ℹ Config vault already mounted"
fi
echo ""

# Step 5: Mount audit-logs (RO)
echo "Step 5: Mounting audit-logs (RO)..."
if ! mountpoint -q /mnt/nas/audit-logs 2>/dev/null; then
  sudo mount -t nfs4 -o "${NFS_OPTS_RO}" 192.168.168.39:/export/audit-logs /mnt/nas/audit-logs
  echo "✓ Audit logs mounted"
else
  echo "ℹ Audit logs already mounted"
fi
echo ""

# Step 6: Persist in fstab
echo "Step 6: Persisting mounts in /etc/fstab..."
if ! grep -q "192.168.168.39:/export" /etc/fstab 2>/dev/null; then
  sudo tee -a /etc/fstab > /dev/null << 'FSTAB'

# NAS Mounts (Added 2026-03-15 via NAS Direct Deployment)
192.168.168.39:/export/repositories /mnt/nas/repositories nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576 0 0
192.168.168.39:/export/config-vault /mnt/nas/config-vault nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,ro 0 0
192.168.168.39:/export/audit-logs /mnt/nas/audit-logs nfs4 vers=4.1,proto=tcp,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,ro 0 0
FSTAB
  echo "✓ Mounts persisted to fstab"
else
  echo "ℹ fstab already contains NAS mounts"
fi
echo ""

# Step 7: Setup health check service
echo "Step 7: Setting up NAS health check service..."
sudo tee /etc/systemd/system/nas-health-check.service > /dev/null << 'SERVICE'
[Unit]
Description=NAS Health Check Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nas-health-check.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

sudo tee /etc/systemd/system/nas-health-check.timer > /dev/null << 'TIMER'
[Unit]
Description=NAS Health Check Timer
Requires=nas-health-check.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# Create health check script
sudo tee /usr/local/bin/nas-health-check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -euo pipefail

MOUNT_POINTS=("/mnt/nas/repositories" "/mnt/nas/config-vault" "/mnt/nas/audit-logs")
LOG_FILE="/var/log/nas-health-check.log"

{
  echo "[$(date -Iseconds)] NAS Health Check"
  
  for mount in "${MOUNT_POINTS[@]}"; do
    if mountpoint -q "$mount" 2>/dev/null; then
      echo "✓ $mount: OK (mounted)"
    else
      echo "✗ $mount: FAILED (not mounted)"
      # Attempt remount
      mount -a || echo "✗ Auto-remount failed"
    fi
  done
  
  echo "---"
} >> "$LOG_FILE"
SCRIPT

sudo chmod +x /usr/local/bin/nas-health-check.sh
echo "✓ Health check service created"
echo ""

# Step 8: Enable systemd services
echo "Step 8: Enabling systemd services..."
sudo systemctl daemon-reload
sudo systemctl enable nas-health-check.timer
sudo systemctl start nas-health-check.timer
echo "✓ Services enabled and started"
echo ""

# Step 9: Verify mounts
echo "Step 9: Verifying all mounts..."
df -h /mnt/nas/{repositories,config-vault,audit-logs}
echo ""

# Step 10: System status
echo "Step 10: System status..."
echo "NFS Protocol Versions:"
mount | grep "/mnt/nas" | grep -o "vers=[0-9.]*"
echo ""
echo "✓ STAGE 2 COMPLETE"
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Next steps:"
echo "  1. Monitor: sudo systemctl status nas-health-check.timer"
echo "  2. Logs: journalctl -u nas-health-check.service -f"
echo "  3. Test: ls -la /mnt/nas/repositories"
echo "  4. Verify: df -h /mnt/nas/*"
echo "────────────────────────────────────────────────────────────"
```

### Verification (after Stage 2):
```bash
# Check all mounts are active
df -h /mnt/nas/*

# Check NFS protocol
mount | grep "/mnt/nas"

# Check health check status
sudo systemctl status nas-health-check.timer

# View health check logs
journalctl -u nas-health-check.service -n 20
```

**✅ Once verified, deployment is complete!**

---

## 📋 DEPLOYMENT CHECKLIST

### ✅ Pre-Stage 1 (On NAS 192.168.168.39):
- [ ] SSH access as kushin77
- [ ] sudo access configured
- [ ] Disk space available (/export)
- [ ] NFS server installed (`sudo systemctl status nfs-server`)

### ✅ Stage 1 Execution:
- [ ] Create /export directories
- [ ] Backup /etc/exports
- [ ] Add NFS export entries
- [ ] Run exportfs -r
- [ ] Verify with showmount -e localhost

### ✅ Post-Stage 1 Verification:
- [ ] All 3 exports visible in showmount output
- [ ] Export permissions correct (rw for dev, ro for worker)
- [ ] IP restrictions in place (only .31 and .42)

### ✅ Pre-Stage 2 (On Dev Node 192.168.168.31):
- [ ] SSH access as akushnir
- [ ] sudo access configured
- [ ] NFS client installed (`apt-get install nfs-common`)
- [ ] Network connectivity to NAS (ping 192.168.168.39)

### ✅ Stage 2 Execution:
- [ ] Create /mnt/nas mount directories
- [ ] Mount all 3 NFS exports
- [ ] Persist in /etc/fstab
- [ ] Create systemd health check service
- [ ] Enable and start health check timer

### ✅ Post-Stage 2 Verification:
- [ ] All 3 mounts listed in df -h
- [ ] NFS v4.1 protocol confirmed
- [ ] Health check timer active
- [ ] Can read from config-vault
- [ ] Can write to repositories

### ✅ Git Tracking:
- [ ] Commit deployment tracker files
- [ ] Tag deployment version
- [ ] Document changes in git

---

## 🚀 QUICK START

### For NAS Admin (kushin77@192.168.168.39):

```bash
# SSH to NAS
ssh kushin77@192.168.168.39

# Copy Stage 1 script content above and execute
# ... paste and run ...

# Verify
sudo showmount -e localhost
```

### For Dev Node (akushnir@192.168.168.31):

```bash
# SSH to dev node
ssh akushnir@192.168.168.31

# Copy Stage 2 script content above and execute
# ... paste and run ...

# Verify
df -h /mnt/nas/*
sudo systemctl status nas-health-check.timer
```

---

## 📊 DEPLOYMENT METRICS

| Phase | Duration | Status |
|-------|----------|--------|
| NAS Configuration (Stage 1) | ~2 min | Ready |
| Dev Node Setup (Stage 2) | ~3 min | Ready |
| Validation | ~1 min | Ready |
| **Total** | **~6 min** | **Ready** |

---

## 🔍 MONITORING AFTER DEPLOYMENT

```bash
# Monitor health checks (real-time)
journalctl -u nas-health-check.service -f

# View current mounts
df -h /mnt/nas/*

# Check mount status
mount | grep nas

# NFS statistics
nfsstat -s

# Check for stale handles
grep -i stale /var/log/syslog
```

---

## ❌ TROUBLESHOOTING

### "Connection refused" during Stage 2 mounting:
```bash
# On NAS: Verify exports are active
sudo showmount -e localhost

# On NAS: Check NFS server status
sudo systemctl status nfs-server

# On NAS: Restart if needed
sudo systemctl restart nfs-server
sudo exportfs -ra
```

### "Stale NFS handle" error:
```bash
# Auto-generated by health check, or manual:
sudo umount -lf /mnt/nas/repositories
sudo mount -a
```

### Permission "Read-only file system":
```bash
# Confirm you're on the RW mount
mount | grep repositories | grep -v ro

# If it shows "ro", there's a configuration issue
# Check /etc/exports on NAS for correct permissions
```

---

## 📞 SUPPORT

- **NAS Issues**: Check `/etc/exports` and `sudo showmount -e localhost`
- **Mount Issues**: Check `/etc/fstab` and `mount` output
- **Network Issues**: Test connectivity with `ping 192.168.168.39`
- **Permissions**: Verify `/etc/exports` entries for correct IPs
- **Health Check**: View logs with `journalctl -u nas-health-check.service`

---

**Generated**: 2026-03-15  
**Status**: 🟢 Production Ready  
**No Manual Intervention Required After Stages Complete**
