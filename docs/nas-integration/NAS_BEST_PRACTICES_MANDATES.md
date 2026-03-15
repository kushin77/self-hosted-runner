# 📋 NAS BEST PRACTICES & MANDATORY CONSTRAINTS

**Date**: March 15, 2026  
**Target**: Development Node (192.168.168.31)  
**NAS Server**: 192.168.168.100  
**Status**: 🟢 ENFORCEABLE STANDARDS

---

## Executive Summary

This document defines mandatory constraints and best practices for NAS integration with the development node. These are not recommendations—they are **REQUIRED for production deployment**.

All items marked **[MANDATORY]** must be enforced. Violations indicate infrastructure incorrectness.

---

## 🎯 MANDATORY CONSTRAINTS

### Constraint 1: NFS Protocol Version [MANDATORY]

**Requirement**: Use NFS v4.1 only  
**Enforcement**: Version checked on mount, mount fails if wrong version  
**Rationale**: v4 is stateful and secure; v3 is stateless and legacy

```bash
# ✅ CORRECT
mount -t nfs4 192.168.168.100:/home/svc-nas/repositories /mnt/nas/repositories

# ❌ INCORRECT (will fail)
mount -t nfs /192.168.168.100:/repositories...  # Wrong version
```

**Validation**:
```bash
mount | grep "nfs4"  # Must show nfs4
```

---

### Constraint 2: Transport Protocol [MANDATORY]

**Requirement**: TCP only (never UDP)  
**Enforcement**: All mounts use `proto=tcp`  
**Rationale**: TCP ensures reliability; UDP may lose packets on congestion

```bash
# ✅ CORRECT
mount -t nfs4 ... -o proto=tcp,vers=4.1

# ❌ INCORRECT
mount -t nfs3 ... -o proto=udp
```

**Validation**:
```bash
mount | grep "proto=tcp"  # Must show TCP
```

---

### Constraint 3: Read-Write vs Read-Only [MANDATORY]

**Requirement**: Mount permissions match data type
- Repositories (IaC code): **Read-Write** for dev node
- Config Vault: **Read-Only** for all nodes (except NAS admin)
- Audit Logs: **Read-Only** for all nodes (immutable)

```bash
# ✅ CORRECT - Repositories RW
mount ... /mnt/nas/repositories -o vers=4.1,proto=tcp,rw,async

# ✅ CORRECT - Config RO
mount ... /mnt/nas/config-vault -o vers=4.1,proto=tcp,ro

# ✅ CORRECT - Audit RO
mount ... /mnt/nas/audit-logs -o vers=4.1,proto=tcp,ro

# ❌ INCORRECT
mount ... /mnt/nas/config-vault -o rw  # Should be read-only!
```

**Validation**:
```bash
mount | grep "/mnt/nas/repositories" | grep -q "rw" && echo "✓"
mount | grep "/mnt/nas/config-vault" | grep -q "ro" && echo "✓"
mount | grep "/mnt/nas/audit-logs" | grep -q "ro" && echo "✓"
```

---

### Constraint 4: Performance Parameters [MANDATORY]

**Requirement**: Specific NFS tuning parameters for optimal performance

```bash
# Block sizes must be 1MB (1048576 bytes)
rsize=1048576     # Read size
wsize=1048576     # Write size

# Timeouts and retries
timeo=30          # 3-second initial timeout
retrans=3         # Retry up to 3 times

# Locking
nolock            # Disable NLM (Network Lock Manager) for dev node
```

**Why**:
- Block sizes: 1MB = optimal performance for modern networks
- Timeouts: 30 deciseconds = 3 seconds (balances latency vs reliability)
- Retries: 3 attempts = good for transient failures
- nolock: Unnecessary overhead on local dev node

**Validation**:
```bash
mount | grep "rsize=1048576" && mount | grep "wsize=1048576" && echo "✓"
```

---

### Constraint 5: Mount Persistence [MANDATORY]

**Requirement**: All mounts must persist across reboots  
**Enforcement**: Entries in `/etc/fstab` with systemd automounting

```bash
# /etc/fstab entry REQUIRED
192.168.168.100:/home/svc-nas/repositories /mnt/nas/repositories nfs4 \
  vers=4.1,proto=tcp,rw,async,hard,timeo=30,retrans=3,rsize=1048576,wsize=1048576,nolock,\
  x-systemd.automount,x-systemd.mount-timeout=30s 0 0
```

**Validation**:
```bash
grep "^192.168.168.100" /etc/fstab | wc -l  # Must show 3 entries
```

---

### Constraint 6: Firewall Rules [MANDATORY]

**Requirement**: Firewall must allow NFS port 2049 (TCP)

```bash
# ✅ CORRECT - Allow NFS
sudo ufw allow from 192.168.168.100 to any port 2049 proto tcp
sudo ufw allow from any to 192.168.168.100 port 2049 proto tcp

# ✅ CORRECT - Allow rpcbind (111)
sudo ufw allow from 192.168.168.100 to any port 111 proto tcp
```

**Validation**:
```bash
sudo ufw status | grep 2049
```

---

### Constraint 7: Network Isolation [MANDATORY]

**Requirement**: NAS traffic on dedicated network (192.168.168.0/24)  
**Enforcement**: All NFS use this subnet only

```bash
# ✅ CORRECT - On isolated network
NAS_IP=192.168.168.100    # Isolated network
DEV_IP=192.168.168.31     # Same network

# ❌ INCORRECT
mount from different subnet / through internet  # Massive security risk
```

---

### Constraint 8: Export Permissions [MANDATORY]

**Requirement**: NAS exports with restrictive permissions  
**NAS Admin Responsibility**: Verify `/etc/exports`

```bash
# ✅ CORRECT - /etc/exports on NAS (read-only IaC, explicit perms)
/home/svc-nas/repositories 192.168.168.31(rw,sync,root_squash,anonuid=nobody)
/home/svc-nas/repositories 192.168.168.42(ro,sync,root_squash,anonuid=nobody)
/home/svc-nas/config-vault 192.168.168.0/24(ro,sync,root_squash,anonuid=nobody)
/home/svc-nas/audit-logs   192.168.168.0/24(ro,sync,root_squash,anonuid=nobody)

# ❌ INCORRECT - World-readable
/home/svc-nas/repositories *(rw,no_root_squash,no_all_squash)  # MASSIVE SECURITY HOLE
```

---

### Constraint 9: Mount Point Permissions [MANDATORY]

**Requirement**: Correct filesystem permissions on mount points

```bash
# ✅ CORRECT
/mnt/nas               755  (drwxr-xr-x)
/mnt/nas/repositories  755  (drwxr-xr-x)
/mnt/nas/config-vault  755  (drwxr-xr-x)
/mnt/nas/audit-logs    700  (drwx------)  # Restricted audit access

# ❌ INCORRECT
chmod 777 /mnt/nas  # Everyone can write? NO!
```

**Validation**:
```bash
stat -c "%A %n" /mnt/nas/repositories | grep "755"
```

---

### Constraint 10: Disk Space Monitoring [MANDATORY]

**Requirement**: Alert if NAS usage exceeds 85%  
**Enforcement**: Automated monitoring script runs every 15 minutes

```bash
# Current usage must be < 85%
df /mnt/nas/repositories | awk 'NR==2 {if ($5 > 85) exit 1}'  # ✓ If passes

# Alert if:
# - Usage > 85%
# - Inode usage > 90%
# - Any mount becomes unavailable
```

---

### Constraint 11: Timeout & Reliability [MANDATORY]

**Requirement**: All mounts must be `hard` mounts (never `soft`)

```bash
# ✅ CORRECT - Hard mount (retries forever on failure)
mount -o hard,timeo=30,retrans=3 ...

# ❌ INCORRECT - Soft mount (fails quickly, data loss risk)
mount -o soft,timeo=5,retrans=1 ...
```

**Why**: Hard mounts prevent silent data loss. Soft mounts cause I/O errors after timeout.

---

## 🛡️ SECURITY BEST PRACTICES

### Practice 1: Root Squashing [MANDATORY]

**Requirement**: All NAS exports must use `root_squash`

```bash
# ✅ CORRECT - /etc/exports on NAS
/home/svc-nas/repositories 192.168.168.0/24(rw,sync,root_squash,anonuid=nobody)

# Effect: root on client mapped to "nobody" on NAS
# Prevents root on dev node from becoming root on NAS
```

**Validation on NAS**:
```bash
grep "root_squash" /etc/exports | wc -l  # Must show 3+ entries
```

---

### Practice 2: SSH-Only Admin Access [MANDATORY]

**Requirement**: Only NAS admin can modify exports  
**Enforcement**: SSH key-based only, no passwords

```bash
# ✅ CORRECT - Modify exports via SSH
ssh -i /home/svc-nas/.ssh/nas-admin-key svc-nas@192.168.168.100 \
  "sudo nano /etc/exports"

# ❌ INCORRECT
Allow development node to modify /etc/exports  # NO!
```

---

### Practice 3: Audit Immutability [MANDATORY]

**Requirement**: Audit logs cannot be modified or deleted

```bash
# ✅ CORRECT - Mount as read-only with append-only flag
mount /mnt/nas/audit-logs -o ro  # Read-only prevents modifications
# Files on NAS have append-only flag: chattr +a

# Prevents any accidental or malicious changes
```

---

### Practice 4: No World-Readable Exports [MANDATORY]

**Requirement**: Never use `*` in `/etc/exports`

```bash
# ✅ CORRECT - Explicit subnets
/home/svc-nas/repositories 192.168.168.31(rw,sync,root_squash)
/home/svc-nas/repositories 192.168.168.42(ro,sync,root_squash)

# ❌ INCORRECT - World-readable
/home/svc-nas/repositories *(rw,sync)  # EVERYONE can mount!
```

---

## 📊 PERFORMANCE BEST PRACTICES

### Practice 1: Async Writes for Dev [MANDATORY]

**Requirement**: Dev node repositories use async writes  
**Rationale**: Improves performance for development workflow

```bash
# ✅ CORRECT - Dev repositories (async)
mount ... /mnt/nas/repositories -o async,rw

# ✅ CORRECT - Config/Audit (sync, read-only anyway)
mount ... /mnt/nas/config-vault -o sync,ro
```

---

### Practice 2: Connection Pooling [RECOMMENDED]

**Requirement**: Enable TCP connection pooling

```bash
# In /etc/nfs.conf or kernel parameter
tcp_slot_table_entries=256
```

---

### Practice 3: Disable Nagle's Algorithm [RECOMMENDED]

```bash
# Reduce latency on LAN
echo "net.ipv4.tcp_nodelay=1" >> /etc/sysctl.conf
sysctl -p
```

---

## 🔍 MONITORING & HEALTH CHECKS

### Required Health Checks [MANDATORY]

Run every **15 minutes** automatically:

```bash
# 1. Mount point accessible
mountpoint -q /mnt/nas/repositories || alert

# 2. NAS reachable
ping -c 1 192.168.168.100 || alert

# 3. NFS process active
pgrep nfsd || alert

# 4. Disk usage < 85%
df /mnt/nas | awk 'NR==2 {if ($5 > 85) alert}'

# 5. Inode usage < 90%
df -i /mnt/nas | awk 'NR==2 {if ($5 > 90) alert}'

# 6. Mount responsive (can read files)
ls /mnt/nas/repositories >/dev/null || alert
```

**Automation**:
```bash
# Via cron
*/15 * * * * /opt/automation/scripts/nas-integration/validate-nfs-mounts.sh --repair

# Via systemd timer
systemctl enable nas-nfs-mounts.timer
```

---

## 🚨 DISASTER RECOVERY

### Stale NFS Mount - What to Do [MANDATORY]

**Symptom**: `mount` shows entries but `ls` hangs

**Solution**:
```bash
# 1. Force lazy unmount
sudo umount -l /mnt/nas/repositories

# 2. Wait 5 seconds
sleep 5

# 3. Verify unmounted
mountpoint -q /mnt/nas/repositories && echo "Still mounted" || echo "Unmounted"

# 4. Remount via fstab
mount /mnt/nas/repositories

# 5. Verify responsive
timeout 5 ls /mnt/nas/repositories || echo "Failed"
```

**Prevention**:
- Health checks every 15 minutes (automatic)
- Auto-repair enabled
- Hard mounts with high retry count

---

### NAS Server Unavailable [MANDATORY]

**Scenario**: NAS goes down; dev node should NOT hang

**Expected Behavior**:
```bash
# With hard mounts (CORRECT):
# - New I/O operations wait/retry (block application)
# - Existing connections timeout after retrans * timeo (90 sec)
# - systemd can set mount-timeout for boot timeout

# With soft mounts (INCORRECT - data loss risk):
# - I/O fails immediately
# - Silent data loss possible
```

**Prevention**:
- Monitor NAS health 24/7
- Alert on NAS unavailability
- Document manual failover procedure

---

## 📋 ENFORCEMENT CHECKLIST

Use this checklist after deployment:

```bash
# [ ] NFS v4.1 only
mount | grep "nfs4" | wc -l  # Should be 3

# [ ] TCP protocol
mount | grep "proto=tcp" | wc -l  # Should be 3

# [ ] Correct R/W permissions
mount | grep "repositories" | grep -q "rw" && echo "✓"
mount | grep "config-vault" | grep -q "ro" && echo "✓"
mount | grep "audit-logs" | grep -q "ro" && echo "✓"

# [ ] Block sizes correct
mount | grep "rsize=1048576,wsize=1048576" | wc -l  # Should be 3

# [ ] Persistent in fstab
grep "^192.168.168.100" /etc/fstab | wc -l  # Should be 3

# [ ] Mount points responsive
for mp in/mnt/nas/{repositories,config-vault,audit-logs}; do
  timeout 5 ls "$mp" >/dev/null && echo "✓ $mp" || echo "✗ $mp"
done

# [ ] Firewall allows NFS
sudo ufw status | grep 2049

# [ ] Systemd services active
systemctl is-active nas-nfs-mounts.service
systemctl is-active nas-nfs-mounts.timer
```

---

## 🔐 SECURITY AUDIT CHECKLIST

```bash
# [ ] No world-readable exports
ssh svc-nas@192.168.168.100 "grep '^\*' /etc/exports" && echo "FAIL" || echo "✓"

# [ ] Root squashing enabled
ssh svc-nas@192.168.168.100 "grep 'root_squash' /etc/exports" | wc -l  # Should be 3+

# [ ] Audit logs read-only on client
mount | grep "audit-logs" | grep -q "ro" && echo "✓"

# [ ] Only SSH for admin access
ssh svc-nas@192.168.168.100 "sudo iptables -L | grep -i telnet" && echo "FAIL" || echo "✓"

# [ ] Mount point permissions restrictive
stat -c "%a %n" /mnt/nas/audit-logs | grep "700" && echo "✓"
```

---

## 📊 MONITORING DASHBOARD

Key metrics to track:

| Metric | Target | Alert |
|--------|--------|-------|
| Mount availability | 100% | < 99.9% |
| NAS uptime | 99.9% | < 99% |
| NFS latency | < 10ms | > 50ms |
| Disk usage | < 70% | > 85% |
| Inode usage | < 70% | > 90% |
| Stale mounts | 0 | > 0 |

---

## 📚 REFERENCE COMMANDS

```bash
# Setup NFS mounts
sudo bash /opt/automation/scripts/nas-integration/setup-nfs-mounts.sh mount

# Validate mounts
bash /opt/automation/scripts/nas-integration/setup-nfs-mounts.sh validate

# Auto-repair
sudo bash /opt/automation/scripts/nas-integration/setup-nfs-mounts.sh repair

# Show status
bash /opt/automation/scripts/nas-integration/setup-nfs-mounts.sh status

# View NFS logs
tail -f /var/log/nas-integration/nfs-mounts.log
tail -f /var/log/nas-integration/nfs-validate.log
```

---

## ❌ COMMON MISTAKES TO AVOID

1. **Using NFS v3 instead of v4**
   - ❌ Wrong: `mount -t nfs ...`
   - ✅ Right: `mount -t nfs4 ...`

2. **Using UDP instead of TCP**
   - ❌ Wrong: `mount -o proto=udp`
   - ✅ Right: `mount -o proto=tcp`

3. **Soft mounts (causes silent data loss)**
   - ❌ Wrong: `mount -o soft`
   - ✅ Right: `mount -o hard`

4. **No root_squash (security hole)**
   - ❌ Wrong: `/home/svc-nas *(rw,no_root_squash)`
   - ✅ Right: `/home/svc-nas 192.168.168.31(rw,root_squash)`

5. **Write-accessible audit logs (violates immutability)**
   - ❌ Wrong: Mount audit-logs as read-write
   - ✅ Right: Always mount audit-logs as read-only

6. **No persistence (mounts lost on reboot)**
   - ❌ Wrong: Manual mounts only
   - ✅ Right: Entries in `/etc/fstab` + systemd automount

7. **No health monitoring**
   - ❌ Wrong: Set and forget
   - ✅ Right: Health checks every 15 minutes

---

## 📞 COMPLIANCE & AUDIT

These constraints are **NON-NEGOTIABLE** for production:

✅ **Compliance**: These meet enterprise NAS standards  
✅ **Security**: These prevent common NAS vulnerabilities  
✅ **Performance**: These optimize for LAN usage  
✅ **Reliability**: These ensure data integrity  
✅ **Auditability**: These provide verification mechanisms  

All deployments must pass this checklist before going live.

---

**Status**: 🟢 enforceable standards  
**Version**: 1.0 | **Date**: March 15, 2026  
**Next Review**: March 22, 2026
