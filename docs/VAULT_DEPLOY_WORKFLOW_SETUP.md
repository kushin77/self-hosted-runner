# Vault Configuration for Deploy Workflow (deploy-immutable-ephemeral.yml)

This guide walks through the complete setup required to run the `deploy-immutable-ephemeral.yml` workflow with Vault-backed SSH key authentication.

## Quick Summary

The `deploy-immutable-ephemeral.yml` workflow requires:
1. **GitHub Repository Secrets** for Vault authentication (VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID)
2. **Vault AppRole** configured with appropriate policies
3. **SSH Key stored in Vault** at `secret/data/runnercloud/deploy-ssh-key` with a `private_key` field
4. **Deploy user configured** on target runner hosts with SSH key and passwordless sudo (if needed)

## Prerequisites

- Access to Vault as an admin (to set up AppRole)
- SSH access to runner hosts
- GitHub admin access to the repository (to add secrets)
- `jq` and `curl` installed for CLI testing

## Setup Steps

### Step 1: Prepare SSH Key (if not already available)

If you don't have a dedicated deploy SSH key, generate one:

```bash
# Generate SSH key (no passphrase for automation)
ssh-keygen -t rsa -b 4096 -f ./deploy_id_rsa -N ""

# Output the public key for later
cat deploy_id_rsa.pub
```

### Step 2: Configure Vault (AppRole & Secret)

#### 2.1 Enable AppRole Auth Method (if not already enabled)

```bash
# SSH to Vault server or use Vault CLI with auth
export VAULT_ADDR=https://vault.internal.company.com:8200
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
# Enable AppRole if not already enabled
vault auth enable approle 2>/dev/null || true
```

#### 2.2 Create AppRole for Deploy

```bash
# Create AppRole
vault write auth/approle/role/deploy-runner \
  token_policies="deploy-runner-policy" \
  token_ttl=1h \
  bind_secret_id=true \
  secret_id_ttl=24h

echo "✓ AppRole created: deploy-runner"
```

#### 2.3 Create Vault Policy

```bash
# Create policy for deploy automation
vault policy write deploy-runner-policy - <<'POLICY_EOF'
path "secret/data/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/metadata/runnercloud/deploy-ssh-key" {
  capabilities = ["read"]
}
path "secret/data/runnercloud/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/runnercloud/*" {
  capabilities = ["read", "list"]
}
POLICY_EOF

echo "✓ Policy created: deploy-runner-policy"
```

#### 2.4 Store SSH Key in Vault

```bash
# Store SSH key in Vault KV2
vault kv put secret/runnercloud/deploy-ssh-key \
  private_key=@./deploy_id_rsa

echo "✓ SSH key stored at: secret/data/runnercloud/deploy-ssh-key"

# Verify storage
vault kv get secret/runnercloud/deploy-ssh-key
```

#### 2.5 Generate AppRole Credentials

```bash
# Get Role ID
ROLE_ID=$(vault read auth/approle/role/deploy-runner/role-id -format=json | jq -r '.data.role_id')

# Generate Secret ID
SECRET_ID=$(vault write -f auth/approle/role/deploy-runner/secret-id -format=json | jq -r '.data.secret_id')

echo "VAULT_ROLE_ID=$ROLE_ID"
echo "VAULT_SECRET_ID=$SECRET_ID"

# Save these values for GitHub Secrets configuration
```

### Step 3: Configure GitHub Repository Secrets

Navigate to your GitHub repository → Settings → Secrets and variables → Actions

Add the following secrets:

| Secret Name | Value |
|-------------|-------|
| `VAULT_ADDR` | `<VAULT_ADDR>` |
| `VAULT_ROLE_ID` | `<VAULT_ROLE_ID_PLACEHOLDER>` |
| `VAULT_SECRET_ID` | `<VAULT_SECRET_ID_PLACEHOLDER>` |

**Example using GitHub CLI:**

```bash
# Use the GitHub CLI to set repository secrets with placeholder values shown below.
gh secret set VAULT_ADDR --body "<VAULT_ADDR>"
gh secret set VAULT_ROLE_ID --body "<VAULT_ROLE_ID_PLACEHOLDER>"
gh secret set VAULT_SECRET_ID --body "<VAULT_SECRET_ID_PLACEHOLDER>"

# Verify
gh secret list
```

### Step 4: Configure Deploy User on Runner Hosts

#### 4.1 Add Public SSH Key to Runner Hosts

On each runner host (as root or with sudo):

```bash
# Create deploy user if not exists
useradd -m -s /bin/bash deploy || true

# Add public key to authorized_keys
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh

# Paste the public key from Step 1
echo "<deploy_id_rsa.pub content>" >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh

echo "✓ SSH key configured for deploy user"
```

#### 4.2 Configure Passwordless Sudo (optional but recommended)

If Ansible playbooks need to run with `become: yes`, configure passwordless sudo:

```bash
# Add to /etc/sudoers (use visudo to edit safely)
echo "deploy ALL=(ALL) NOPASSWD: /bin/systemctl, /bin/systemd-tmpfiles, /bin/mkdir, /usr/bin/docker" | sudo tee /etc/sudoers.d/deploy

chmod 440 /etc/sudoers.d/deploy

echo "✓ Passwordless sudo configured for deploy user"
```

### Step 5: Test the Workflow

#### 5.1 Test Vault Authentication First

```bash
# Run from terminal to validate Vault connectivity
curl -s -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
  -H "Content-Type: application/json" \
  -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${VAULT_SECRET_ID}\"}" \
  | jq .

# Should return a client_token in `.auth.client_token`
```

#### 5.2 Trigger Workflow Dispatch

Navigate to Actions → Deploy Rotation Automation → Run workflow

Configure inputs:
- **inventory_file**: `ansible/inventory/staging` (or your inventory path)
- **vault_secret_path**: `secret/data/runnercloud/deploy-ssh-key` (leave default)
- **ansible_user**: `deploy`
- **dry_run**: `true` (for first test)
- **verify_idempotence**: `true`

#### 5.3 Monitor Run

Watch the workflow run:
- Check "Fetch deploy SSH key from Vault" step (should authenticate successfully)
- Check "Run Ansible" step (should connect via SSH)
- Check "Verify idempotence" step (should report no changes on second run)

### Step 6: Automate Runs

Once tested successfully, you can:

1. **Schedule Deploy Rotation (Cron)**:
   
   Add a scheduled workflow trigger to `.github/workflows/deploy-immutable-ephemeral.yml`:
   
   ```yaml
   schedule:
     - cron: '0 2 * * *'  # Daily at 2 AM UTC
   ```

2. **Dispatch via CLI**:
   
   ```bash
   gh workflow run deploy-immutable-ephemeral.yml \
     --ref main \
     -f inventory_file='ansible/inventory/staging' \
     -f vault_secret_path='secret/data/runnercloud/deploy-ssh-key' \
     -f ansible_user='deploy' \
     -f dry_run='false' \
     -f verify_idempotence='true'
   ```

## Troubleshooting

### Vault Authentication Fails

**Error**: `Failed to authenticate to Vault`

**Solutions**:
- Verify `VAULT_ADDR` is reachable: `curl -k https://vault.internal/v1/sys/health`
- Verify `VAULT_ROLE_ID` and `VAULT_SECRET_ID` are correct
- Check Vault server logs: `vault audit list` and review auth failures
- Ensure AppRole is enabled: `vault auth list`

### SSH Key Not Found

**Error**: `Failed to fetch SSH key from Vault`

**Solutions**:
- Verify secret exists: `vault kv get secret/runnercloud/deploy-ssh-key`
- Verify policy allows read: `vault policy read deploy-runner-policy`
- Check path format: should be `secret/data/runnercloud/deploy-ssh-key`

### Ansible SSH Connection Fails

**Error**: `Permission denied (publickey)` or `host is unreachable`

**Solutions**:
- Verify public key is in `/home/deploy/.ssh/authorized_keys` on runner hosts
- Verify SSH private key was fetched correctly: Check workflow step output
- Test SSH manually: `ssh -i /path/to/deploy_id_rsa deploy@runner-host`
- Check runner inventory file syntax

### Sudo Permissions Denied

**Error**: `sudo: a password is required`

**Solutions**:
- Verify passwordless sudo is configured: `sudo -l -U deploy`
- Check `/etc/sudoers.d/deploy` exists and has correct permissions (440)
- If not running with sudo, remove `become: yes` from Ansible playbook

## Rotation & Security

### Rotate AppRole Secret ID (Monthly)

```bash
# Generate new Secret ID
NEW_SECRET_ID=$(vault write -f auth/approle/role/deploy-runner/secret-id -format=json | jq -r '.data.secret_id')

# Update GitHub Secret
gh secret set VAULT_SECRET_ID --body "$NEW_SECRET_ID"

# Test the new credential works
curl -s -X POST "${VAULT_ADDR}/v1/auth/approle/login" \
  -H "Content-Type: application/json" \
  -d "{\"role_id\":\"${VAULT_ROLE_ID}\",\"secret_id\":\"${NEW_SECRET_ID}\"}" \
  | jq .

# Revoke old Secret ID if needed (Vault tracks secret ID generation time)
```

### Audit Vault Access

```bash
# View AppRole auth log
vault audit list

# Check for failed logins
vault audit enable file file_path=/vault/logs/audit.log 2>/dev/null || true

# Search for CI AppRole activity
grep "deploy-runner" /vault/logs/audit.log | tail -20
```

## References

- [Vault AppRole Auth Method](https://www.vaultproject.io/docs/auth/approle)
- [Vault KV Secret Engine](https://www.vaultproject.io/docs/secrets/kv/kv-v2)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Ansible SSH Configuration](https://docs.ansible.com/ansible/latest/user_guide/connection_details.html)

## See Also

- [VAULT_CI_SETUP.md](VAULT_CI_SETUP.md) - General Vault CI integration
- [IMMUTABLE_EPHEMERAL_IDEMPOTENT.md](IMMUTABLE_EPHEMERAL_IDEMPOTENT.md) - Deploy workflow design
