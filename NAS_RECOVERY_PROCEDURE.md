# NAS Server Recovery Procedure - URGENT

**Status**: 🔴 CRITICAL - NAS server (192.168.168.39) is blocking all repository development

**Problem**: 
- NAS exports visible via `showmount -e` ✅
- TCP/IP connectivity working ✅  
- NFS portmap (111) accessible ✅
- NFS port 2049 accessible ✅
- **BUT**: Mount RPC calls to mountd service (port 40553) timeout — NO RESPONSE

**Root Cause**:
The NAS server's mountd daemon is not responding to NFS mount RPC requests. This indicates:
1. mountd service not running or crashed
2. NFS exports not reloaded after configuration change
3. RPC protocol mismatch or corruption
4. NAS server kernel issue or firewall blocking RPC responses

## REQUIRED FIXES (NAS Admin Must Execute):

### Step 1: SSH to NAS Server
```bash
ssh <admin>@192.168.168.39
```

### Step 2: Check NFS Services
```bash
sudo systemctl status nfs-server
sudo systemctl status nfs-mountd  # if available
sudo systemctl status rpc-mountd  # alternative name

# Check if services are running
sudo systemctl list-units --type=service | grep -i nfs
sudo systemctl list-units --type=service | grep -i mount
```

### Step 3: Reload NFS Exports
```bash
# CRITICAL: Force reload of all exports
sudo exportfs -arv

# Verify export includes 192.168.168.42
sudo exportfs -v
```

### Step 4: Restart NFS Services
```bash
sudo systemctl restart nfs-server
sudo systemctl restart nfs-mountd  # if available
# OR restart all NFS-related services
sudo systemctl restart nfs-utils  # on RHEL/CentOS
```

### Step 5: Verify NFS Daemon Listening
```bash
# Check RPC registry
rpcinfo -p localhost | grep mount
rpcinfo -p localhost | grep nfs

# Verify ports listening
sudo netstat -tlnp | grep -E 'mountd|nfsd'
# OR use ss:
sudo ss -tlnp | grep -E 'mount|nfs'
```

### Step 6: Test from Worker-42
```bash
# From worker-42:
ssh akushnir@192.168.168.42
showmount -e 192.168.168.39  # should succeed
sudo mount -t nfs -o vers=3,proto=tcp,nolock,soft,timeo=10 192.168.168.39:/nas /nas
mount | grep /nas  # should show mounted
```

## WORKER SIDE - Automated Recovery

Once NAS server is fixed, run on worker-42:
```bash
ssh akushnir@192.168.168.42
sudo systemctl restart nas-mount.service
sudo mount -a  # activate fstab entries
mount | grep 192.168.168.39  # verify
```

## DIAGNOSTIC COMMANDS (For Troubleshooting)

```bash
# From worker-42: Test RPC connectivity
rpcinfo -u 192.168.168.39 100005  # mountd program
rpcinfo -p 192.168.168.39 | grep mount

# Check NFS kernel module
modinfo nfs
lsmod | grep nfs

# Monitor mount attempt with strace
sudo strace -e trace=network timeout 5 mount -t nfs -o vers=3,proto=tcp 192.168.168.39:/nas /mnt 2>&1 | tail -50

# tcpdump for mount RPC traffic
sudo tcpdump -i any -n host 192.168.168.39 and port 40553 -w /tmp/mount.pcap
# Then mount in another terminal
# Analyze: tcpdump -r /tmp/mount.pcap
```

## IMPACT (While NAS is Down):

- ✅ Runners still operational (all 3 online)
- ✅ Cost tracking still working
- ✅ Monitoring stack operational
- ❌ Repository codebase NOT accessible
- ❌ Config-vault NOT accessible
- ❌ Development blocked

## MANDATORY FIX TIMELINE:

**This is a blocking issue** - NAS mount is marked MANDATORY in deployment requirements.

- **Immediate (0-1h)**: NAS admin run Steps 1-6 above
- **Verification (1-2h)**: Worker attempts automated mount  
- **Escalation (>2h)**: Contact infrastructure team for NAS server reboot if services won't start

---

## FILES INVOLVED:

- **Worker-42 fstab**: `/etc/fstab` (configured `/nas` entry with `noauto`)
- **Worker-42 service**: `/etc/systemd/system/nas-mount.service` (auto-retry every 15s)
- **NAS exports**: `/etc/exports` on 192.168.168.39 (requires `exportfs -a` reload)

## NOTES:

- Mount will auto-retry every 15 seconds via systemd
- Once NAS responds, worker will automatically mount
- No worker-side changes needed - only NAS server fix required
