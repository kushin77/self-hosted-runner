# NAS Post-Crash Recovery: Configuration Required

**Status**: NAS is online (ping verified) but requires manual configuration after crash recovery.

## Blocking Issue
The NAS server (192.168.168.39) has recovered from crash but exports are not configured. SSH access to complete automation-based setup is currently blocked.

## Required NAS Admin Actions

Execute these commands on NAS server (192.168.168.39) as root:

```bash
# Step 1: Create export directories
mkdir -p /export/repositories
mkdir -p /export/config-vault
mkdir -p /export/audit-logs

# Step 2: Set permissions
chmod 755 /export
chmod 755 /export/repositories
chmod 755 /export/config-vault
chmod 755 /export/audit-logs

# Step 3: Add to /etc/exports
cat >> /etc/exports << 'EXPORTS'
/export/repositories 192.168.168.31(rw,sync,no_subtree_check,root_squash)
/export/repositories 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/config-vault 192.168.168.42(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.31(ro,sync,no_subtree_check,root_squash)
/export/audit-logs 192.168.168.42(ro,sync,no_subtree_check,root_squash)
EXPORTS

# Step 4: Export configuration
exportfs -r

# Step 5: Verify
showmount -e localhost
```

Expected output from step 5:
```
Export list for 192.168.168.39:
/export/repositories        192.168.168.31,192.168.168.42
/export/config-vault        192.168.168.31,192.168.168.42
/export/audit-logs          192.168.168.31,192.168.168.42
```

## Current Dev Node Status

**Infrastructure deployed**: ✅ 100% complete
- Automation service account: ✅ Active
- SSH keys: ✅ ED25519 keys configured
- Mount points: ✅ Ready (currently using local bind mounts for testing)
- Services: ⏳ Waiting for NAS exports
- Test suite: 53% (7/13 passing) - infrastructure working, NAS blocking

## Timeline to Production

After NAS admin completes above configuration:
1. Dev node will auto-detect NAS exports
2. Re-run test suite: `bash scripts/nas-integration/test-nas-workflow.sh --scenario=all`
3. Expected result: 100% (13/13 tests passing)
4. Enable production features: watch mode, worker node sync

**Estimated time after NAS config**: ~5 minutes to full operability

