# 🚀 NAS NFS MOUNT DEPLOYMENT - IMMEDIATE EXECUTION

**Status**: APPROVED - PROCEEDING NOW  
**Date**: March 14, 2026  
**NAS Server**: 192.16.168.39  
**Architecture**: Direct NFS v4 mounts on both nodes  
**Estimated Duration**: 10-15 minutes  

---

## 🎯 DEPLOYMENT SUMMARY

Deploying **direct NFS filesystem mounts** instead of rsync:

✅ **Repositories** will be mounted at `/nas/repositories` on both nodes  
✅ **Config Vault** will be mounted at `/nas/config-vault` on both nodes  
✅ Both dev node (.31) and worker node (.42) will mount simultaneously  
✅ Systemd units ensure mounts persist across reboots  
✅ NFS v4 with TCP protocol for maximum reliability  
✅ Hardened mount options: hard timeout + 3 retrans for resilience

---

## ⚡ IMMEDIATE EXECUTION

### Step 1: Verify Preflight (30 seconds)

```bash
cd /home/akushnir/self-hosted-runner

# Quick connectivity test
./deploy-nas-nfs-mounts.sh verify
```

**Expected**: All connectivity checks pass

### Step 2: Execute Full NFS Mount Deployment (10-15 minutes)

```bash
# FULL DEPLOYMENT - both worker and dev nodes
./deploy-nas-nfs-mounts.sh full
```

**This will:**
1. Install NFS client tools on both nodes
2. Create `/nas` directory structure
3. Mount `/repositories` via NFS v4
4. Mount `/config-vault` via NFS v4
5. Deploy systemd mount units (persistent)
6. Update `/etc/fstab` for boot-time mounting
7. Verify mounts are readable/writable

### Step 3: Verify Mounts (2 minutes)

```bash
# Check current mount status
./deploy-nas-nfs-mounts.sh status

# Run detailed health check
./scripts/healthcheck-nas-nfs-mounts.sh
```

**Expected**: Both mounts active on both nodes

### Step 4: Test Access (1 minute)

```bash
# SSH to worker and test
ssh automation@192.168.168.42 "ls -lh /nas/repositories | head -10"

# SSH to dev and test
ssh automation@192.168.168.31 "ls -lh /nas/repositories | head -10"
```

**Expected**: Files visible, accessible, and readable

---

## 📊 ARCHITECTURE AFTER DEPLOYMENT

```
┌─────────────────────────────────────────────────────────┐
│                  NAS (192.16.168.39)                    │
│  /repositories  (/mnt/export1)                          │
│  /config-vault  (/mnt/export2)                          │
└────────────────┬──────────────┬───────────────────────┘
                 │              │
        ┌────────▼──────┐   ┌──▼────────────┐
        │ Dev Node .31  │   │ Worker .42    │
        ├───────────────┤   ├───────────────┤
        │ /nas/repos ◄──┼───┤◄─ NFS v4 (TCP)
        │ /nas/config◄──┼───┤      Mount    
        │ (mounted)     │   │ (persistent)  
        │ Always sync   │   │               
        │ with NAS      │   │ Systemd units │
        └───────────────┘   └───────────────┘
```

---

## 🔄 NFS MOUNT OPTIONS

**Each mount uses production-grade settings:**

```
proto=tcp           → TCP protocol (reliable, firewall-friendly)
vers=4.1            → NFS v4.1 (latest stable version)
hard                → Persist on network issues (don't fail soft)
timeo=600           → 60-second timeout (10 min for hard retry)
retrans=3           → Retry 3 times before failing
rsize=131072        → 128KB read buffer (performance)
wsize=131072        → 128KB write buffer (performance)
x-systemd.automount → Lazy mount on first access
```

---

## ✅ SUCCESS INDICATORS

After deployment, verify:

```bash
# 1. Mounts are active
mount | grep nfs4
# Expected: 2 lines (repositories + config-vault)

# 2. Systemd units are enabled
systemctl status nas-mounts.target
# Expected: active (running) or active (exited)

# 3. Files are accessible
ls -lh /nas/repositories | wc -l
# Expected: Large number (all repo files)

# 4. Disk usage visible
df -h /nas/
# Expected: Size of NAS exports

# 5. Performance acceptable
dd if=/dev/zero of=/nas/repositories/.test bs=1M count=10 count_in_flight=4 && rm /nas/repositories/.test
# Expected: Completes in <5 seconds
```

---

## 🛠️ ADVANCED COMMANDS

```bash
# Deploy worker node only
./deploy-nas-nfs-mounts.sh worker

# Deploy dev node only
./deploy-nas-nfs-mounts.sh dev

# Dry-run (see what would happen)
./deploy-nas-nfs-mounts.sh --dry-run full

# Unmount all (if needed)
./deploy-nas-nfs-mounts.sh umount

# Check status on worker
ssh automation@192.168.168.42 "mount | grep nfs4"

# Check status on dev  
ssh automation@192.168.168.31 "mount | grep nfs4"

# Force remount
ssh automation@192.168.168.42 "sudo mount -o remount /nas/repositories"

# View systemd unit status (worker)
ssh automation@192.168.168.42 "sudo systemctl status nas-repositories.mount"
```

---

## 📊 MONITORING & MAINTENANCE

### Continuous Health Check (Deploy on worker node)

Create a systemd timer:

```bash
# Copy health check script to worker
scp scripts/healthcheck-nas-nfs-mounts.sh automation@192.168.168.42:/opt/scripts/

# Run periodically (e.g., every 15 minutes via cron)
ssh automation@192.168.168.42 \
    "echo '*/15 * * * * /opt/scripts/healthcheck-nas-nfs-mounts.sh >> /var/log/nas-health.log 2>&1' | sudo tee -a /etc/crontab"
```

### View Recent Health Status

```bash
# Check latest health report
ssh automation@192.168.168.42 "tail -50 /var/log/nas-health.log"

# Monitor mount issues
grep -i "error\|fail" /var/log/nas-nfs-health.log
```

---

## 🚨 TROUBLESHOOTING

### "NFS server not responding"

```bash
# Verify NAS is up
ping 192.16.168.39

# Check NFS exports on NAS
ssh admin@192.16.168.39 "showmount -e"

# Check firewall (NFS uses port 2049)
sudo ufw status | grep 2049
ssh admin@192.16.168.39 "sudo ufw allow 2049"

# Try manual mount with verbose
sudo mount -t nfs4 -v 192.16.168.39:/repositories /nas/repositories
```

### "Permission denied" after mount

```bash
# Check mount ownership
ls -ld /nas/repositories

# Fix permissions
sudo chown automation:automation /nas/repositories
sudo chmod 755 /nas/repositories

# Verify NAS export permissions
ssh admin@192.16.168.39 "exportfs -v"
```

### "Stale NFS file handle"

```bash
# Unmount and remount
sudo umount /nas/repositories
sudo mount -t nfs4 -o proto=tcp,vers=4.1,hard,timeo=600,retrans=3 \
    192.16.168.39:/repositories /nas/repositories
```

### "Device or resource busy" when unmounting

```bash
# Force lazy unmount
sudo umount -l /nas/repositories

# Or find what's using it
lsof | grep /nas/repositories
kill -9 <PID>  # Kill the process if safe
sudo umount /nas/repositories
```

---

## 🔒 SECURITY BEST PRACTICES

✅ **Implemented:**
- NFS v4 only (no v3)
- TCP protocol (UDP would be less secure)
- Hard mounts (prevent silent failures)
- Systemd unit protection (immutable on boot)

✅ **Verify on NAS:**
- Firewall allows only authorized IPs
- NFS exports restricted to .31 and .42
- No world-writable exports
- Audit logging enabled on NAS

```bash
# On NAS server, verify /etc/exports
ssh admin@192.16.168.39 "cat /etc/exports"

# Expected: Something like
# /repositories 192.168.168.31(rw,sync) 192.168.168.42(rw,sync)
# /config-vault 192.168.168.31(rw,sync) 192.168.168.42(rw,sync)
```

---

## 📞 DEPLOYMENT CHECKLIST

Before starting:
- [ ] NAS IP verified: 192.16.168.39
- [ ] Network connectivity confirmed (ping test)
- [ ] SSH access working to both nodes
- [ ] /etc/exports configured on NAS
- [ ] Backups of current configs completed

During deployment:
- [ ] Monitor deployment log for errors
- [ ] Watch for network issues
- [ ] Check systemd unit deployment

After deployment:
- [ ] Both mounts active on worker
- [ ] Both mounts active on dev
- [ ] Files accessible and readable
- [ ] Health check passes
- [ ] Services running normally

---

## 🎯 NEXT IMMEDIATE STEPS

1. **NOW**: Run `./deploy-nas-nfs-mounts.sh verify` (30 sec)
2. **THEN**: Run `./deploy-nas-nfs-mounts.sh full` (12-15 min)
3. **AFTER**: Run `./scripts/healthcheck-nas-nfs-mounts.sh` (1 min)
4. **FINALLY**: Verify from both nodes (1 min)

**Total execution time: ~18 minutes**

---

🚀 **Ready to deploy!** Execute now with no further delays:

```bash
cd /home/akushnir/self-hosted-runner
./deploy-nas-nfs-mounts.sh full
```
