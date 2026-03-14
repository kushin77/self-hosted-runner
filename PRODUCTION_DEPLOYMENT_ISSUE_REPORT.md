# 🚨 Production Deployment - SSH Authentication Issue

**Date:** March 14, 2026, 23:08 UTC  
**Status:** Stage 3 Paused - SSH Authentication Required  
**Severity:** Blocking (Stage 3 cannot proceed)

---

## Current Situation

Orchestrator successfully completed:
- ✅ Stage 1: Constraint Validation - PASSED
- ✅ Stage 2: Preflight Checks - PASSED (3/4 critical)
- ⏳ Stage 3: NAS NFS Mounts - **BLOCKED on SSH authentication**

### Error Details

```
akushnir@192.168.168.42: Permission denied (publickey,password).
```

**Cause:** SSH key authentication failed when attempting to deploy to worker node

---

## Quick Diagnostics

### SSH Connectivity Status
- ✓ Worker node **IS** reachable (SSH server responding)
- ✓ SSH key **EXISTS** at ~/.ssh/id_ed25519 (ED25519 format)
- ✗ SSH authentication **FAILED** with permission denied

### Likely Causes
1. SSH public key not installed on worker's authorized_keys
2. Different SSH user required
3. Key permissions issue
4. Worker SSH configuration mismatch

---

## Resolution Options

### Option A: Install SSH Key on Worker (Recommended)

**On worker node (192.168.168.42):**
```bash
# As root or with sudo:
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Get public key from dev machine
# On dev: cat ~/.ssh/id_ed25519.pub

# Add to authorized_keys on worker:
echo "YOUR_PUBLIC_KEY_HERE" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

**Verify from dev:**
```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.168.42 "whoami"
# Should return: root
```

### Option B: Use Different SSH User

If SSH key is already configured for a different user:
```bash
# Modify orchestrator or use override:
ssh -i ~/.ssh/id_ed25519 <username>@192.168.168.42 "id"
```

### Option C: Check SSH Key Format

Verify key is properly formatted:
```bash
# On dev machine:
cat ~/.ssh/id_ed25519 | head -1
# Should show: -----BEGIN OPENSSH PRIVATE KEY-----

ssh-keygen -l -f ~/.ssh/id_ed25519
# Shows key fingerprint
```

---

## Retry Deployment

Once SSH is configured:

```bash
cd /home/akushnir/self-hosted-runner

# Re-run orchestrator (idempotent, safe to retry)
bash deploy-orchestrator.sh full
```

The orchestrator will:
1. Re-validate all constraints (Stage 1)
2. Re-run preflight checks (Stage 2)
3. **Proceed with Stage 3** (NFS mounts) - now with SSH working
4. Continue through stages 4-8

---

## Alternative: Force with Different SSH User

If you know the correct SSH user:
```bash
# Modify orchestrator call or ensure SSH config has:
ssh -i ~/.ssh/id_ed25519 USERNAME@192.168.168.42 "command"
```

---

## Documentation for Future Reference

**SSH Authentication Requirements:**
- Dev machine (192.168.168.31) ← has SSH key
- SSH public key must be on worker (192.168.168.42)
- Typically in `/root/.ssh/authorized_keys` for root access
- Or in `~/.ssh/authorized_keys` for regular user access

**Idempotence Note:** 
Re-running the orchestrator after fixing SSH is safe and will pick up where it left off.

---

**Next Steps:**
1. Copy public key from dev to worker authorized_keys
2. Verify SSH works: `ssh -i ~/.ssh/id_ed25519 root@192.168.168.42`
3. Re-run: `bash deploy-orchestrator.sh full`

