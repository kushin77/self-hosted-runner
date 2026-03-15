# Service Account Setup - Final Status

Date: 2026-03-15 16:15 UTC  
Status: **2/3 COMPLETE - Ready for NAS Testing**

## Completed Deployments ✅

### 1. elevatediq-svc-worker-dev@192.168.168.42
- **Status**: ✅ SSH Key Auth Working
- **Verified**: `whoami` returns `elevatediq-svc-worker-dev`
- **Key**: `secrets/ssh/elevatediq-svc-worker-dev/id_ed25519`  
- **Use Case**: Primary dev node service account

### 2. elevatediq-svc-worker-nas@192.168.168.42
- **Status**: ✅ SSH Key Auth Working  
- **Verified**: `whoami` returns `elevatediq-svc-worker-nas`
- **Key**: `secrets/ssh/elevatediq-svc-worker-nas/id_ed25519`
- **Use Case**: NAS worker service account

### 3. elevatediq-svc-dev-nas@192.168.168.39
- **Status**: ⏳ Manual Setup Required
- **Required Action**: SSH to 192.168.168.39 and run account setup
- **Key**: `secrets/ssh/elevatediq-svc-dev-nas/id_ed25519`
- **Command**:
  ```bash
  sudo useradd -r -s /bin/bash -m "/home/elevatediq-svc-nas" elevatediq-svc-nas 2>/dev/null || true
  sudo mkdir -p /home/elevatediq-svc-nas/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF6xEytY+bFL8dUeNLHVIrAPTuEJs0L2Z0ZF0jQ47iHf" | sudo tee /home/elevatediq-svc-nas/.ssh/authorized_keys
  sudo chown -R elevatediq-svc-nas:elevatediq-svc-nas /home/elevatediq-svc-nas/.ssh
  sudo chmod 700 /home/elevatediq-svc-nas/.ssh
  sudo chmod 600 /home/elevatediq-svc-nas/.ssh/authorized_keys
  ```

## Testing Instructions

### Test .42 Accounts
```bash
cd /home/akushnir/self-hosted-runner
source .env.service-accounts

# Test 1
ssh -i "$ELEVATEDIQ_SVC_WORKER_DEV_KEY" elevatediq-svc-worker-dev@192.168.168.42 "id"

# Test 2
ssh -i "$ELEVATEDIQ_SVC_WORKER_NAS_KEY" elevatediq-svc-worker-nas@192.168.168.42 "id"
```

### Run Stress Test (once .39 is ready)
```bash
bash scripts/nas-integration/stress-test-nas.sh --aggressive --monitor
```

## Architecture

```
Local Dev Machine (this server)
  ├── elevatediq-svc-worker-dev@.42 ✅
  ├── elevatediq-svc-worker-nas@.42 ✅
  └── elevatediq-svc-dev-nas@.39 ⏳
      
192.168.168.42 (Production Worker)
  ├── elevatediq-svc-worker-dev ✅
  └── elevatediq-svc-worker-nas ✅

192.168.168.39 (NAS)
  └── elevatediq-svc-nas ⏳ (setup required)
```

## Next Steps

1. **Immediate**: Complete setup on .39 by SSH and running account creation
2. **Post-.39**: Rerun stress test with all 3 accounts active
3. **Optional**: Store private keys in Google Secret Manager (GSM)
4. **Optional**: Set up automated key rotation (90-day cycle)

## Environment Setup

```bash
source /home/akushnir/self-hosted-runner/.env.service-accounts
```

Provides:
- `$ELEVATEDIQ_SVC_WORKER_DEV_KEY`
- `$ELEVATEDIQ_SVC_WORKER_NAS_KEY`  
- `$ELEVATEDIQ_SVC_DEV_NAS_KEY`
- Convenience aliases: `ssh-dev-worker`, `ssh-nas-worker`, `ssh-dev-nas`
