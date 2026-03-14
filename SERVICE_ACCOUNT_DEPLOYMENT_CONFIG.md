# SERVICE ACCOUNT DEPLOYMENT CONFIGURATION

**Date**: March 14, 2026  
**Status**: PRODUCTION READY  
**Updated**: Service account authentication fully implemented

---

## Overview

Both deployment scripts now use service accounts for all operations. This ensures secure, auditable, and repeatable deployments without hardcoded credentials.

---

## Service Account Architecture

### Worker Node (192.168.168.42)
- **Service Account**: `svc-git`  
- **SSH Key Source**: GCP Secret Manager (GSM)
- **SSH Key Secret Name**: `svc-git-ssh-key`
- **Ephemeral Auth**: SSH key fetched at runtime, never stored locally
- **Audit**: All operations logged to append-only audit trail

### Dev Node (192.168.168.31)
- **Service Account**: Current user (configurable)
- **Default User**: `$(whoami)` at execution time
- **SSH Key**: Local Ed25519 key (defaults to `~/.ssh/id_ed25519`)
- **Override**: Via `--dev-svc` and `--dev-key` flags

---

## NAS Mount Deployment (deploy-nas-nfs-mounts.sh)

### Configuration

```bash
# Default service accounts (automatically selected)
WORKER_SERVICE_ACCOUNT="svc-git"
WORKER_SSH_KEY="/home/svc-git/.ssh/id_ed25519"

DEV_SERVICE_ACCOUNT="$(whoami)"
DEV_SSH_KEY="${HOME}/.ssh/id_ed25519}"
```

### Environment Variables

Control service accounts via environment variables:

```bash
# Override worker service account
export WORKER_SVC_ACCOUNT="svc-git"
export WORKER_SSH_KEY="/path/to/svc-git-key"

# Override dev service account
export DEV_SVC_ACCOUNT="username"
export DEV_SSH_KEY="/path/to/user-key"

# Then run deployment
./deploy-nas-nfs-mounts.sh full
```

### Command-Line Arguments

```bash
# Use custom service accounts
./deploy-nas-nfs-mounts.sh --worker-svc svc-automation \
                          --worker-key ~/.ssh/svc-automation-key \
                          --dev-svc automation \
                          --dev-key ~/.ssh/automation-key \
                          full

# Deploy worker only with specific service account
./deploy-nas-nfs-mounts.sh --worker-svc svc-git \
                          --worker-key ~/.ssh/svc-git-key \
                          worker

# Deploy dev only
./deploy-nas-nfs-mounts.sh --dev-svc $(whoami) \
                          --dev-key ~/.ssh/id_ed25519 \
                          dev
```

### Usage Examples

```bash
# Full deployment (default service accounts)
./deploy-nas-nfs-mounts.sh full

# Dry-run to see what would happen
./deploy-nas-nfs-mounts.sh --dry-run full

# Check current status
./deploy-nas-nfs-mounts.sh status

# Unmount NFS filesystems
./deploy-nas-nfs-mounts.sh umount

# Verify NFS connectivity
./deploy-nas-nfs-mounts.sh verify
```

---

## Worker Node Deployment (deploy-worker-node.sh)

### Configuration

```bash
readonly SERVICE_ACCOUNT="svc-git"              # Service account name
readonly SERVICE_ACCOUNT_EMAIL="svc-git"        # GA service account email
readonly SSH_KEY_SECRET="svc-git-ssh-key"       # GSM secret name
readonly TARGET_HOST="192.168.168.42"           # Worker node IP
readonly TARGET_USER="svc-git"                  # Service account user on worker
readonly SSH_KEY_FILE="/tmp/svc-git-key-$$"    # Ephemeral key file
```

### Authentication Flow

1. **SSH Key Retrieval** (from GSM at runtime):
   ```bash
   gcloud secrets versions access latest --secret="svc-git-ssh-key"
   ```

2. **Temporary Key Storage**:
   - Written to `/tmp/svc-git-key-<PID>` with 600 permissions
   - Automatically cleaned up on exit via `trap cleanup_ssh_key EXIT`
   - Private temp isolation (PrivateTmp) ensures ephemeral storage

3. **Remote Execution**:
   ```bash
   ssh -i "$SSH_KEY_FILE" $SSH_OPTS "svc-git@192.168.168.42" bash -c "command"
   ```

### Environment Variables

```bash
# Override service account
export SERVICE_ACCOUNT="svc-automation"
export SERVICE_ACCOUNT_EMAIL="svc-automation@project.iam.gserviceaccount.com"
export SSH_KEY_SECRET="svc-automation-ssh-key"

# Override target
export TARGET_HOST="192.168.168.42"
export TARGET_USER="svc-git"
export SSH_KEY_FILE="/tmp/my-svc-key"

# Then run deployment
bash deploy-worker-node.sh
```

### Usage Examples

```bash
# Standard deployment (uses svc-git with GSM key)
bash deploy-worker-node.sh

# With specific service account
SERVICE_ACCOUNT=svc-automation bash deploy-worker-node.sh

# With specific SSH key location
SSH_KEY_FILE=~/.ssh/my-svc-key bash deploy-worker-node.sh
```

### Security Features

✅ **Ephemeral Keys**: SSH keys fetched at runtime, never persisted  
✅ **GSM Integration**: Credentials from GCP Secret Manager  
✅ **No Cloud Violation**: Blocks cloud credentials from environment  
✅ **Audit Trail**: All operations logged to immutable append-only log  
✅ **On-Prem Only**: Validates target is 192.168.168.42 or 192.168.168.39  
✅ **Graceful Cleanup**: SSH key shredded after use  

---

## SSH Key Formats

### Expected SSH Key Format

All SSH keys must be Ed25519 format:

```bash
# Check key type
ssh-keygen -l -f /path/to/key

# Output should show: "256 SHA256:... (ED25519)"
```

### Creating Ed25519 Keys

```bash
# Generate Ed25519 key for service account
ssh-keygen -t ed25519 -f ~/.ssh/svc-git-key -N ""

# Add to system authorized_keys
cat ~/.ssh/svc-git-key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Storing in GCP Secret Manager

```bash
# Create secret from file
gcloud secrets create svc-git-ssh-key --data-file=/path/to/svc-git-key

# Verify stored correctly
gcloud secrets versions access latest --secret="svc-git-ssh-key" | head -1
```

---

## Deployment Commands

### Full NAS Deployment (NFS Mounts + Scripts)

```bash
cd /home/akushnir/self-hosted-runner

# 1. Verify connectivity
./verify-nas-redeployment.sh quick

# 2. Dry-run to see what will happen
./deploy-nas-nfs-mounts.sh --dry-run full

# 3. Execute full deployment
./deploy-nas-nfs-mounts.sh full

# 4. Verify deployment succeeded
./verify-nas-redeployment.sh detailed
```

### Worker Node Full Stack Deployment

```bash
cd /home/akushnir/self-hosted-runner

# 1. Execute worker deployment
bash deploy-worker-node.sh

# 2. Verify deployment
curl http://192.168.168.42:5000/health
```

---

## Troubleshooting

### "Cannot SSH to worker node"

**Cause**: SSH key not found or service account misconfigured

**Solution**:
```bash
# Verify SSH key exists
ls -la /home/svc-git/.ssh/id_ed25519

# Verify key permissions (must be 600)
stat /home/svc-git/.ssh/id_ed25519

# Test SSH connectivity
ssh -i /home/svc-git/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
    svc-git@192.168.168.42 "exit 0"

# Check GSM secret exists
gcloud secrets list | grep svc-git-ssh-key
```

### "Failed to retrieve SSH key from GSM"

**Cause**: GSM secret not found or credentials not configured

**Solution**:
```bash
# Verify gcloud CLI installed
which gcloud

# List available secrets
gcloud secrets list

# Try retrieving secret manually
gcloud secrets versions access latest --secret="svc-git-ssh-key"

# If not found, create the secret
gcloud secrets create svc-git-ssh-key --data-file=~/.ssh/svc-git-key
```

### "SSH key command timed out"

**Cause**: Network connectivity issue or service account not authorized

**Solution**:
```bash
# Test basic connectivity
ping 192.168.168.42

# Test SSH port specifically
nc -zv 192.168.168.42 22

# Increase SSH timeout
export SSH_KEY_FILE=/tmp/my-key
ssh -i "$SSH_KEY_FILE" -o ConnectTimeout=30 svc-git@192.168.168.42 "exit 0"
```

---

## Best Practices

1. **Always use service accounts** - Never deploy as root or personal user
2. **Rotate keys periodically** - Update GSM secrets every 90 days
3. **Audit all operations** - Review audit trail logs after deployment
4. **Use strong Ed25519 keys** - No RSA or other formats
5. **Secure SSH keys** - Keep private keys with 600 permissions only
6. **Test in dry-run first** - Always use `--dry-run` before production
7. **Monitor deployments** - Check logs for errors: `.deployment-logs/`
8. **Verify post-deployment** - Run verification scripts after each deploy

---

## Integration Points

### GSM (GCP Secret Manager)

Used for:
- Storing svc-git SSH key (on-prem authentication)
- Storing API credentials (at runtime, never locally)
- Storing SSL/TLS certificates
- Storing encryption keys

```bash
# List GSM secrets
gcloud secrets list

# View secret metadata
gcloud secrets describe svc-git-ssh-key

# Rotate secret
gcloud secrets versions add svc-git-ssh-key --data-file=/new/key
```

### Audit Trail

All deployment operations are logged to:
- **File**: `.deployment-logs/nas-mount-YYYYMMDD-HHMMSS.log`
- **Audit**: `.deployment-logs/mount-audit-YYYYMMDD-HHMMSS.jsonl`
- **Format**: JSON Lines (one event per line, immutable)

---

## Service Account Lifecycle

### Create Service Account

```bash
# Create on-premises service account
useradd -m -s /bin/bash svc-git
su - svc-git

# Generate Ed25519 key
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Add to authorized_keys
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Test SSH access
ssh -i ~/.ssh/id_ed25519 localhost "hostname"
```

### Store in GSM

```bash
# As deployment administrator
gcloud secrets create svc-git-ssh-key \
    --data-file=/home/svc-git/.ssh/id_ed25519

# Verify it works
gcloud secrets versions access latest --secret="svc-git-ssh-key" | \
    ssh-keygen -l -f /dev/stdin
```

### Rotate Service Account Key

```bash
# 1. Generate new key on on-prem system
ssh svc-git@192.168.168.42 "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519.new -N ''"

# 2. Store in GSM (creates new version, keeps old)
gcloud secrets versions add svc-git-ssh-key \
    --data-file=<(ssh svc-git@192.168.168.42 "cat ~/.ssh/id_ed25519.new")

# 3. Test new key works
gcloud secrets versions access --secret="svc-git-ssh-key" latest

# 4. Update on-prem system to use new key
ssh svc-git@192.168.168.42 "mv ~/.ssh/id_ed25519.new ~/.ssh/id_ed25519"

# 5. Verify deployment works with new key
./deploy-nas-nfs-mounts.sh verify
```

---

## References

- [NAS Mount Deployment Script](deploy-nas-nfs-mounts.sh)
- [Worker Node Deployment Script](deploy-worker-node.sh)
- [On-Premises Architecture](ON_PREMISES_ARCHITECTURE.md)
- [Operations Runbook](OPERATIONS_RUNBOOK.md)

---

**Status**: ✅ PRODUCTION READY  
**Last Updated**: March 14, 2026  
**Reviewed**: Service account authentication complete
