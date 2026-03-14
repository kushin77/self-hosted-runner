# SSH Service Accounts - Keys-Only Deployment Guide

**No Passwords. No Prompts. Pure SSH Key Authentication.**

## Overview

This guide documents the complete setup for SSH service accounts that use **secrets management** (GSM/Vault) and **SSH keys exclusively** — with zero password prompts anywhere in the deployment pipeline.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  GSM / Vault / KMS                  │  ← Secrets Backend
│         SSH Private/Public Key Pairs (AES-256)      │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
    ┌──────────────────────────────┐
    │   Secrets Directory          │
    │  secrets/ssh/<account>/      │
    │  - id_ed25519                │
    │  - id_ed25519.pub            │
    └─────────────┬────────────────┘
                  │
       ┌──────────┼──────────┐
       ▼          ▼          ▼
   Source      Target    Local
   Hosts       Hosts     SSH Config
   (deploy)    (auth)    (~/.ssh/*)
   
   All via SSH keys, never password authentication
```

## Key Components

### 1. SSH Configuration (`~/.ssh/config`)

Enforces key-only authentication:
```
PasswordAuthentication no
PubkeyAuthentication yes
PreferredAuthentications publickey
BatchMode yes
StrictHostKeyChecking no
UserKnownHostsFile /dev/null
```

### 2. Environment Variables

Prevent password prompts at OS level:
```bash
export SSH_ASKPASS=none              # Disable password prompts
export SSH_ASKPASS_REQUIRE=never     # Force no prompts
export DISPLAY=""                    # No GUI for password dialogs
```

### 3. SSH Command Options

Every SSH command includes:
```bash
ssh -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -o PreferredAuthentications=publickey \
    -i /path/to/key \
    user@host
```

## Deployment Routes

| Source | Target | Account | Purpose |
|--------|--------|---------|---------|
| 192.168.168.31 (dev) | 192.168.168.42 (worker) | `elevatediq-svc-worker-dev` | Automated deployments |
| 192.168.168.39 (nas) | 192.168.168.42 (worker) | `elevatediq-svc-worker-nas` | Backup/archive sync |
| 192.168.168.31 (dev) | 192.168.168.39 (nas) | `elevatediq-svc-dev-nas` | Data pipeline |

## Setup Process

### Step 1: Configure SSH for Keys-Only

```bash
bash scripts/ssh_service_accounts/configure_ssh_keys_only.sh setup
```

This performs:
1. Creates/updates `~/.ssh/config` with key-only rules
2. Adds environment variables to `~/.bashrc`
3. Deploys service account keys to `~/.ssh/svc-keys/`
4. Sets correct permissions (600)

### Step 2: Verify Configuration

```bash
bash scripts/ssh_service_accounts/test_ssh_keys_only.sh all
```

Tests:
- ✓ SSH_ASKPASS environment variables
- ✓ Service account keys exist and readable
- ✓ SSH config has PasswordAuthentication=no
- ✓ Keys are locally accessible
- ✓ SSH connections work without passwords

### Step 3: Deploy Service Accounts (No Passwords)

```bash
bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh
```

Deployment sequence:
1. Creates service accounts on target hosts (via sudo)
2. Installs public keys to `authorized_keys`
3. Distributes private keys to source hosts
4. Tests connections (no interactive prompts)
5. Marks deployment as complete (state files)

## How It Works - Technical Details

### Phase 1: Key Configuration

**File**: `configure_ssh_keys_only.sh`

```bash
# Disable password prompts globally
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# SSH config entry
Host 192.168.168.* dev-elevatediq* nas-elevatediq*
    PasswordAuthentication no
    BatchMode yes
    IdentitiesOnly yes
    IdentityFile ~/.ssh/svc-keys/*_key
```

### Phase 2: SSH Command Execution

**File**: `automated_deploy_keys_only.sh`

```bash
# SSH helper function
ssh_cmd() {
    ssh -o StrictHostKeyChecking=no \
        -o BatchMode=yes \
        -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey \
        -i "$SSH_KEY_PATH" \
        "$target"
}

# Usage - no password possible
ssh_cmd "user@192.168.168.42" "whoami"
```

### Phase 3: Secrets Management Integration

Keys sourced from:
1. **Primary**: `secrets/ssh/<account>/id_ed25519` (local)
2. **Secondary**: Google Secret Manager (if available)
3. **Tertiary**: Vault integration (optional)

### Phase 4: Verification

**File**: `test_ssh_keys_only.sh`

```bash
# Test with strict key-only settings
ssh -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -i "$key" "$user@$host" \
    "whoami"
```

If this command:
- ✓ Succeeds → Key is valid and deployed
- ✗ Fails → Key issue, identity mismatch, or host problems

## SSH Key Locations

### Source Directory (Secret Backend)
```
secrets/ssh/
├── elevatediq-svc-worker-dev/
│   ├── id_ed25519           ← Private key
│   ├── id_ed25519.pub       ← Public key
│   └── key-info.json        ← Metadata
├── elevatediq-svc-worker-nas/
│   ├── id_ed25519
│   ├── id_ed25519.pub
│   └── key-info.json
└── elevatediq-svc-dev-nas/
    ├── id_ed25519
    ├── id_ed25519.pub
    └── key-info.json
```

### Local Working Directory
```
~/.ssh/svc-keys/
├── elevatediq-svc-worker-dev_key    ← Cached locally
├── elevatediq-svc-worker-nas_key
└── elevatediq-svc-dev-nas_key
```

### On Target Hosts
```
/home/<account>/.ssh/authorized_keys
  ↑ Contains public key for each service account
```

## Deployment Verification

### Test 1: Key Exists and Readable
```bash
test -r ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key && echo "✓ Key readable"
```

### Test 2: Environment Configured
```bash
[ "$SSH_ASKPASS" = "none" ] && echo "✓ No password prompts"
```

### Test 3: SSH Connection Works
```bash
ssh -o BatchMode=yes -o PasswordAuthentication=no \
    -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
    elevatediq-svc-worker-dev@192.168.168.42 whoami
```

### Test 4: No Password Prompts
```bash
# This should immediately fail or succeed, NEVER prompt
timeout 2 ssh -o BatchMode=yes -o PasswordAuthentication=no \
    invalid@invalid.local 2>&1 | grep -i "password" && echo "FAIL" || echo "PASS"
```

## Troubleshooting

### Issue: `Permission denied (publickey)`

**Cause**: Public key not installed on target

**Solution**:
```bash
# Manually deploy key to target
cat secrets/ssh/elevatediq-svc-worker-dev/id_ed25519.pub | \
  ssh -i ~/.ssh/id_rsa akushnir@192.168.168.42 \
  "sudo tee /home/elevatediq-svc-worker-dev/.ssh/authorized_keys"
```

### Issue: SSH Still Asking for Password

**Cause**: SSH_ASKPASS not set or SSH config incorrect

**Solution**:
```bash
# Verify environment
echo "SSH_ASKPASS=$SSH_ASKPASS"
echo "SSH_ASKPASS_REQUIRE=$SSH_ASKPASS_REQUIRE"

# Reset and reconfigure
source ~/.bashrc
bash scripts/ssh_service_accounts/configure_ssh_keys_only.sh setup
```

### Issue: `Cannot open key: ~/.ssh/svc-keys/...`

**Cause**: Keys not deployed locally

**Solution**:
```bash
bash scripts/ssh_service_accounts/configure_ssh_keys_only.sh deploy-keys
```

### Issue: `StrictHostKeyChecking=no` Still Prompts

**Cause**: SSH may still ask despite settings (older versions)

**Solution**:
```bash
# Add to SSH command
-o UserKnownHostsFile=/dev/null
```

## Automation Integration

### Systemd Timer - Hourly Health Checks

```ini
[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
```

Health check runs with key-only auth:
```bash
bash scripts/ssh_service_accounts/health_check.sh
```

### Systemd Timer - Monthly Credential Rotation

```ini
[Timer]
OnUnitActiveSec=30d
```

Rotation uses GSM for key versioning:
```bash
bash scripts/ssh_service_accounts/credential_rotation.sh rotate-all
```

## Security Properties

| Property | Implementation | Verification |
|----------|---|---|
| **No Passwords** | SSH_ASKPASS=none + BatchMode=yes | `ssh ... -o BatchMode=yes` never prompts |
| **Encrypted at Rest** | AES-256 in GSM | `gcloud secrets versions list` shows encrypted |
| **Encrypted in Transit** | TLS for GSM API | SSH uses port 22 default (wrapped in corp VPN) |
| **Key Rotation** | 90-day auto-rotation via credential_rotation.sh | Versioned in GSM, audit log in logs/ |
| **Audit Trail** | All commands logged to logs/deployment/ | `tail logs/deployment/deployment-*.log` |
| **Immutability** | Keys stored immutable in GSM | One-way sync: secrets → local cache |
| **Idempotency** | State files prevent re-deployment | `.deployment-state/<account>.deployed` |

## Systemd Service Deployment

Once verified, enable continuous automation:

```bash
# Copy systemd units
sudo cp systemd/service-account-*.* /etc/systemd/system/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable service-account-orchestration.service
sudo systemctl enable service-account-health-check.timer
sudo systemctl enable service-account-credential-rotation.timer

# Start timers
sudo systemctl start service-account-health-check.timer
sudo systemctl start service-account-credential-rotation.timer

# Verify
sudo systemctl list-timers --all | grep service-account
```

## Quick Reference

### Complete Setup (from zero)
```bash
# 1. Generate keys (if not done)
bash scripts/ssh_service_accounts/generate_keys.sh

# 2. Configure SSH for keys-only
bash scripts/ssh_service_accounts/configure_ssh_keys_only.sh setup

# 3. Test configuration
bash scripts/ssh_service_accounts/test_ssh_keys_only.sh all

# 4. Deploy service accounts (no passwords)
bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh

# 5. Verify deployment
bash scripts/ssh_service_accounts/health_check.sh
```

### Test a Specific Account
```bash
bash scripts/ssh_service_accounts/test_ssh_keys_only.sh test 192.168.168.42 elevatediq-svc-worker-dev
```

### Manual SSH Test
```bash
ssh -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -i secrets/ssh/elevatediq-svc-worker-dev/id_ed25519 \
    elevatediq-svc-worker-dev@192.168.168.42 \
    "whoami"
```

## Documentation Files

- **This file** (`SSH_KEYS_ONLY_GUIDE.md`) - Complete conceptual guide
- `SERVICE_ACCOUNT_DEPLOYMENT_GUIDE.md` - Original deployment steps
- `SERVICE_ACCOUNT_SETUP_STATUS.md` - Key inventory and status
- `.deployment-state/` - Deployment marker files
- `logs/deployment/` - Detailed execution logs

## Contact & Support

For deployment issues or questions:
1. Check test output: `bash scripts/ssh_service_accounts/test_ssh_keys_only.sh all`
2. Review logs: `tail logs/deployment/deployment-*.log`
3. Verify secrets: `gcloud secrets list --filter="name:ssh-*"`
4. Check SSH config: `cat ~/.ssh/config | grep -A 10 "PasswordAuthentication"`
