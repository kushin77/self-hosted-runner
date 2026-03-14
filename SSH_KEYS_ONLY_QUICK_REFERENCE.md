# SSH Service Accounts - Quick Reference

**🔒 All service accounts use SSH keys exclusively - ZERO password prompts**

## What Was Fixed

Previous behavior: SSH connections asking for passwords
```
user@host's password: [PROMPT - won't work in automation]
```

Current behavior: SSH keys only, no password prompts
```
✓ SSH connects with key or fails immediately
✓ NEVER asks for password
✓ Works in scripts, cron, systemd, CI/CD
✓ Fully automated, silent, no manual intervention
```

## Setup Done

```bash
✅ SSH environment variables configured
   - SSH_ASKPASS=none              (no password dialogs)
   - SSH_ASKPASS_REQUIRE=never     (force this setting)
   - DISPLAY=""                    (no GUI)

✅ SSH configuration hardened
   - PasswordAuthentication no     (reject passwords)
   - PubkeyAuthentication yes      (use keys only)
   - BatchMode yes                 (never prompt)

✅ Service account keys deployed
   - ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key
   - ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key
   - ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key

✅ Deployment scripts created
   - automated_deploy_keys_only.sh    (main deployment)
   - configure_ssh_keys_only.sh       (initial setup)
   - test_ssh_keys_only.sh            (testing & validation)
```

## Test Your Service Accounts

### Quick Test (2 minutes)

```bash
# Source environment
source ~/.bashrc

# Test a connection (will use key, not password)
ssh -o BatchMode=yes -o PasswordAuthentication=no \
    -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
    elevatediq-svc-worker-dev@192.168.168.42 \
    "whoami"
```

Expected result: Service account username, OR immediate error (not password prompt)

### Test All Accounts

```bash
# Run the test suite
export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never
bash scripts/ssh_service_accounts/test_ssh_keys_only.sh all
```

### Test No Password Prompts

```bash
# Try invalid host - should NOT prompt for password
timeout 2 ssh -o BatchMode=yes -o PasswordAuthentication=no \
    invalid@invalid.local 2>&1 | head -1
```

Expected: Immediate error (name resolution, connection refused, etc.)
NOT expected: "Password:" prompt

## Key Concepts

### SSH_ASKPASS=none
- **What it does**: Prevents SSH from opening password dialogs
- **Why it helps**: Automation tools can't interact with dialogs
- **Status**: ✅ Set in ~/.bashrc and current session

### PasswordAuthentication=no
- **What it does**: SSH server refuses all password authentication
- **Why it helps**: Forces key-based auth, no fallback to passwords
- **Status**: ✅ In ~/.ssh/config for service account hosts

### BatchMode=yes
- **What it does**: SSH refuses interactive input (no prompts)
- **Why it helps**: Scripts run unattended without user interaction
- **Status**: ✅ Added to all SSH commands

### Key Files
- **Private keys**: `~/.ssh/svc-keys/<account>_key` (600 permissions)
- **SSH config**: `~/.ssh/config` (with PasswordAuthentication=no)
- **Secret backup**: `secrets/ssh/<account>/id_ed25519` (600 permissions)

## Common Tasks

### Deploy All Service Accounts (No Passwords)
```bash
export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never
bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh
```

### Configure Another User for SSH Keys-Only
```bash
# Run as that user
su - otheruser
bash /path/to/configure_ssh_keys_only.sh setup
```

### Run Health Checks (Uses SSH with Keys Only)
```bash
export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never
bash scripts/ssh_service_accounts/health_check.sh
```

### Manually Deploy a Key to Target
```bash
ssh -i ~/.ssh/id_rsa akushnir@192.168.168.42 \
    "cat >> ~/.ssh/<account>/.ssh/authorized_keys" < \
    secrets/ssh/<account>/id_ed25519.pub
```

### Check SSH Configuration
```bash
grep -E "PasswordAuthentication|BatchMode|PreferredAuth" ~/.ssh/config
```

### Check Environment Variables
```bash
echo "SSH_ASKPASS=$SSH_ASKPASS"
echo "SSH_ASKPASS_REQUIRE=$SSH_ASKPASS_REQUIRE"
source ~/.bashrc  # If not set, reload
echo "SSH_ASKPASS=$SSH_ASKPASS"
```

## Files Location

```
Project:
  /home/akushnir/self-hosted-runner/

SSH Scripts:
  scripts/ssh_service_accounts/
    ├── automated_deploy_keys_only.sh     # Deploy no passwords
    ├── configure_ssh_keys_only.sh        # Setup SSH config
    ├── test_ssh_keys_only.sh             # Verify setup
    ├── health_check.sh                   # Check connectivity
    └── credential_rotation.sh            # Rotate keys (90d)

SSH Keys (Source):
  secrets/ssh/
    ├── elevatediq-svc-worker-dev/
    │   ├── id_ed25519
    │   └── id_ed25519.pub
    ├── elevatediq-svc-worker-nas/
    │   ├── id_ed25519
    │   └── id_ed25519.pub
    └── elevatediq-svc-dev-nas/
        ├── id_ed25519
        └── id_ed25519.pub

SSH Config (User Home):
  ~/.ssh/
    ├── config                       # PasswordAuthentication=no
    └── svc-keys/
        ├── elevatediq-svc-worker-dev_key
        ├── elevatediq-svc-worker-nas_key
        └── elevatediq-svc-dev-nas_key

Logs:
  logs/deployment/deployment-keys-only-*.log
  logs/testing/test-keys-only-*.log
  logs/health/health-check-*.log
```

## Proof: No Passwords

### Example SSH Command
```bash
ssh -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o PubkeyAuthentication=yes \
    -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
    elevatediq-svc-worker-dev@192.168.168.42 \
    "whoami"
```

### Why No Password Prompts?
1. **BatchMode=yes** → No interactive input allowed
2. **PasswordAuthentication=no** → SSH refuses password auth
3. **-i key_file** → Only attempts public key auth
4. **SSH_ASKPASS=none** → No password dialog opens

**Result**: SSH connects with key OR fails immediately. NEVER prompts for password.

## Automation Status

### Ready to Enable (if desired)
```bash
sudo systemctl enable service-account-health-check.timer
sudo systemctl enable service-account-credential-rotation.timer
sudo systemctl start service-account-health-check.timer
sudo systemctl start service-account-credential-rotation.timer
```

### Current Logs
```bash
tail logs/deployment/deployment-keys-only-*.log
tail logs/testing/test-keys-only-*.log
```

## Summary

| Aspect | Status | Details |
|--------|--------|---------|
| **Password-free** | ✅ | SSH_ASKPASS=none + BatchMode=yes |
| **Key-based auth** | ✅ | PasswordAuthentication=no in config |
| **Service accounts** | ✅ | 3 accounts deployed (dev, nas, worker) |
| **Deployment scripts** | ✅ | Keys-only deployment framework ready |
| **Testing** | ✅ | Comprehensive test suite included |
| **Documentation** | ✅ | Complete guides and quick reference |
| **Secrets management** | ✅ | GSM integration for key storage |
| **Automation-ready** | ✅ | Systemd timers configured |

---

**STATUS**: ✅ Service accounts fully deployed using SSH keys exclusively.
**NO PASSWORD PROMPTS ANYWHERE** - All authentication via SSH keys from secrets.
