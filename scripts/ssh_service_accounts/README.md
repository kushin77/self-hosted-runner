# SSH Service Account Setup

This directory contains scripts to set up SSH service accounts for inter-host communication within the self-hosted runner infrastructure.

## Service Accounts

Three service accounts are configured:

1. **elevatediq-svc-worker-dev**
   - From Host: 192.168.168.31 (dev-elevatediq-2)
   - To Host: 192.168.168.42 (worker-prod)
   - Purpose: Development worker communication with production worker

2. **elevatediq-svc-worker-nas**
   - From Host: 192.168.168.39 (nas-elevatediq)
   - To Host: 192.168.168.42 (worker-prod)
   - Purpose: NAS communication with production worker

3. **elevatediq-svc-dev-nas**
   - From Host: 192.168.168.31 (dev-elevatediq-2)
   - To Host: 192.168.168.39 (nas-elevatediq)
   - Purpose: Development communication with NAS

## Setup Process

The setup is performed in two phases:

### Phase 1: Generate Keys

```bash
./generate_keys.sh
```

This script will:
- Generate Ed25519 SSH key pairs for each service account
- Store the keys in `<workspace>/secrets/ssh/<account_name>/`
- Optionally store private keys in Google Secret Manager (GSM)

**Output:** Key pairs for each service account

### Phase 2: Deploy to Hosts

```bash
./deploy_to_hosts.sh
```

This script will:
- Create service accounts on target hosts
- Distribute SSH keys to source hosts
- Configure `authorized_keys` on target hosts
- Test connections between each source/target pair

**Prerequisites:**
- SSH access to all hosts as `akushnir` user (password or key-based)
- Phase 1 keys generated and available locally

## Manual Connection Testing

After setup, you can test connections manually:

```bash
# From host 192.168.168.31 to 192.168.168.42 as elevatediq-svc-worker-dev
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key elevatediq-svc-worker-dev@192.168.168.42

# From host 192.168.168.39 to 192.168.168.42 as elevatediq-svc-worker-nas
ssh -i ~/.ssh/svc-keys/elevatediq-svc-worker-nas_key elevatediq-svc-worker-nas@192.168.168.42

# From host 192.168.168.31 to 192.168.168.39 as elevatediq-svc-dev-nas
ssh -i ~/.ssh/svc-keys/elevatediq-svc-dev-nas_key elevatediq-svc-dev-nas@192.168.168.39
```

## Key Storage

- **Local Storage:** `<workspace>/secrets/ssh/<account_name>/`
  - Private key: `id_ed25519` (mode 600)
  - Public key: `id_ed25519.pub` (mode 644)

- **Remote Storage (GSM):** Each private key is backed up to Google Secret Manager as a secret named after the service account

- **Host Storage:** Keys are deployed to each source host at `~/.ssh/svc-keys/<account_name>_key`

## Troubleshooting

### Connection Refused
- Ensure the service account user exists on the target host: `id elevatediq-svc-*`
- Check `~/.ssh/authorized_keys` on the target host for the public key
- Verify SSH daemon is running: `sudo systemctl status ssh`

### Permission Denied
- Verify the private key permissions are 600: `ls -la ~/.ssh/svc-keys/`
- Check that the public key is in the target's `authorized_keys`: `cat ~/.ssh/authorized_keys | grep -i elevatediq`

### Key Not Found
- Run `generate_keys.sh` to create the keys
- Verify the key files exist in `secrets/ssh/<account_name>/`

## Security Considerations

- Private keys should never be committed to version control
- Keys are stored locally and optionally backed up to GSM
- Service accounts are created as system users (`-r` flag) with restricted shells
- SSH public keys are used for authentication (key-based, not password-based)
- Keys use Ed25519 for improved security

## Integration with Workflow

These service accounts can be used for:
- Automated deployment pipelines
- Cross-host monitoring and health checks
- Log aggregation and centralized monitoring
- Backup and disaster recovery procedures
- Inter-service communication within the infrastructure

## Files

- `generate_keys.sh` - Phase 1: Generate SSH key pairs
- `deploy_to_hosts.sh` - Phase 2: Deploy to hosts and configure
- `setup_service_accounts.sh` - Combined setup script (alternative)
- `README.md` - This documentation
