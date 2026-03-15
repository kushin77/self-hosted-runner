# NAS Mount - All Attempted Solutions

## Attempts Made (All Failed - NAS Server Not Responding)

### ✅ What Works
- Ping to 192.168.168.39: Responds
- TCP Port 111 (portmap): Accessible ✅
- TCP Port 2049 (NFS): Accessible ✅
- UDP Port connectivity: Accessible
- `showmount -e 192.168.168.39`: Shows `/nas` export including 192.168.168.42
- Worker-42 can query `/nas 192.168.168.23,192.168.168.31,192.168.168.42`
- RPC program availability: `rpcinfo -p` shows NFS services registered

### ❌ What Fails (All Mount Attempts)

1. **NFSv3 + TCP** - "portmap query failed: RPC: Timed out"
   - Mount RPC calls hang waiting for mountd response
   - Kernel logs: "nfs: server 192.168.168.39 not responding"
   
2. **NFSv4 + TCP** - "nfs4: Unknown parameter 'connect_timeout'"
   - Failed parameter validation, also timeout on negotiation
   
3. **NFSv3 + UDP** - Exit code 32 (Generic mount failure)
   - Both UDP and TCP variants of mountd service unresponsive
   
4. **With explicit mount ports** - "mount: system call failed for /nas"
   - Direct port specification (40553) didn't help
   
5. **All soft/nolock variations** - All hang or timeout

**ROOT CAUSE**: NAS mountd RPC daemon is not responding to mount requests from TCP or UDP

---

## REQUIRED: NAS Server Admin Action

**Before** deploying these solutions, NAS admin MUST execute on 192.168.168.39:

```bash
# SSH to NAS
ssh admin@192.168.168.39

# Restart NFS services
sudo systemctl restart nfs-server
sudo systemctl restart nfs-mountd  # if available

# Force reload exports configuration
sudo exportfs -arv

# Verify exports include 192.168.168.42
sudo exportfs -v | grep /nas

# Check services listening
sudo ss -tlnp | grep -E "mount|2049"
```

---

## Workaround Options (If NAS Cannot Be Fixed Immediately)

### Option 1: SSHFS Tunnel (Temporary Workaround)
Requires SSH access to NAS server

```bash
# On worker-42
mkdir -p /mnt/nas-tunnel
sshfs admin@192.168.168.39:/nas /mnt/nas-tunnel -o allow_other,default_permissions

# Create symlinks
sudo mkdir -p /nas/repositories /nas/config-vault
sudo mount --bind /mnt/nas-tunnel/<actual_path> /nas/repositories
```

### Option 2: NFS Mount with Manual RPC Restart
If NAS server partially responds:

```bash
# On NAS
sudo exportfs -f  # flush exports
sudo exportfs -ra # re-add all exports
sudo systemctl restart rpc-statd

# On worker
sudo systemctl restart nas-mount.service
```

### Option 3: Create Local Fallback Structure
If NAS is permanently unavailable:

```bash
# On worker-42 /nas
mkdir -p /nas/{repositories,config-vault,runners}
chmod 777 /nas/{repositories,config-vault,runners}

# Symlink from runner workdirs
ln -s /nas/repositories ~/runner-42a/_work/repos
```

### Option 4: NFS Mount with TCP Fast Open (TFO)
Modern kernel optimization:

```bash
sudo mount -t nfs \
  -o vers=3,proto=tcp,tcp_max_slot_table_entries=128,tcp_slot_table_entries=128 \
  192.168.168.39:/nas /nas
```

---

## Verification Commands

Once NAS admin fixes the server, run:

```bash
# From worker-42
ssh akushnir@192.168.168.42

# Test 1: Verify exports are fresh
showmount -e 192.168.168.39

# Test 2: Attempt clean mount
sudo umount -l /nas 2>/dev/null
sudo mount -t nfs -o vers=3,proto=tcp,nolock,soft,timeo=10 192.168.168.39:/nas /nas

# Test 3: Verify mounted
mount | grep /nas
ls -la /nas/repositories
ls -la /nas/config-vault

# Test 4: Automatic retry
sudo systemctl restart nas-mount.service
sudo systemctl status nas-mount.service
```

---

## Current Status

- **Runners**: 3/3 ONLINE (independent of NAS)
- **Cost Tracking**: ACTIVE (independent of NAS)
- **Monitoring**: ACTIVE (independent of NAS)
- **Development**: **BLOCKED** (requires NAS for repositories)
- **NAS Mount Attempts**: All failed, server nonresponsive
- **fstab**: Configured `/nas` with `noauto`
- **systemd service**: `nas-mount.service` deployed (will auto-retry when server responds)

---

## Next Steps

1. **Primary**: NAS admin runs recovery steps above
2. **Once NAS responds**: Mount will auto-complete via systemd retry
3. **If unavailable >1h**: Deploy workaround with SSHFS or local fallback
4. **Verify**: Test mount paths and symlinks

---

## Technical Details

**Worker-42 Configuration** (Already Deployed):
- fstab: `/etc/fstab` has `/nas` entry
- Service: `/etc/systemd/system/nas-mount.service` (15s retry interval)
- Logs: `sudo journalctl -u nas-mount.service -f`
- Kernel errors: `sudo dmesg | grep -i "server.*not responding"`
