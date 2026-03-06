# Immutable, Ephemeral, Idempotent Deployment Guide

This guide explains the four core principles applied to the self-hosted-runner deployment automation: **Immutable**, **Ephemeral**, **Idempotent**, and **Fully Automated**.

## Principles

### 1. Immutable
**Definition**: Deployed artifacts are read-only and are never modified in place. Updates happen by replacement, not editing.

**Implementation**:
- Install binaries to `/usr/libexec` with mode `0555` (read-only for all)
- Configuration files are treated as immutable; changes require redeployment
- Systemd units are deployed with `ProtectSystem=strict` or similar hardening
- No ad-hoc edits in production; all changes go through version control and CI/CD

**Benefits**:
- Prevents configuration drift
- Enables consistent rollback (replace with previous version)
- Simplifies audit and compliance

**Verification**:
```bash
ls -l /usr/libexec/vault-integration*   # Check 0555 permissions
systemctl cat vault-integration.service | grep ProtectSystem
```

### 2. Ephemeral
**Definition**: Runtime state (caches, temporary files, logs) is stored in temporary locations and is cleaned on restart.

**Implementation**:
- Runtime state under `/run` (tmpfs in Linux, deleted on reboot)
- Use systemd `tmpfiles.d` to create and manage ephemeral directories
- Cache directories mounted as tmpfs or temporary volumes
- No persistent state on deployed runners except versioned configs

**Benefits**:
- Simplifies disaster recovery (reboot = clean state)
- Reduces disk footprint
- Ensures secrets/cached data don't persist across restarts

**Verification**:
```bash
systemctl status systemd-tmpfiles-setup.service
ls -la /run/vault-credentials/   # Should be tmpfs
mount | grep /run
```

### 3. Idempotent
**Definition**: Running the deployment multiple times produces the same result. The second and subsequent runs make no changes.

**Implementation**:
- Ansible uses `copy` with `backup` to ensure idempotence
- Tasks check for existing state before making changes
- No destructive operations in playbooks (e.g., no `rm -rf` without guards)
- Workflow includes a second pass in check mode to verify no changes occur

**Benefits**:
- Safe for re-runs (no accidental overwrites or data loss)
- Supports automated remediation (re-run on failure)
- Simplifies CI/CD orchestration

**Verification**:
```bash
# Run the deployment once
ansible-playbook ansible/playbooks/deploy-rotation.yml

# Run again in check mode - should report no changes
ansible-playbook --check ansible/playbooks/deploy-rotation.yml
# Expected output: "changed=0"
```

### 4. Fully Automated & Hands-Off
**Definition**: Human interaction is not required after initial setup. Vault credentials are provided via CI/CD secrets; authentication and deployment are automatic.

**Implementation**:
- GitHub Actions workflow with Vault AppRole authentication
- Secrets stored in repository secrets (not in code)
- Workflow runs non-interactively (no prompts for passwords/passphrases)
- Metrics published and alerting configured
- Rollback and remediation scripts available but not required for common deployments

**Benefits**:
- Faster, more reliable deployments
- Reduced human error
- Enables scheduled/automated updates
- Audit trail via CI/CD logs

**Verification**:
```bash
# Secrets configured
gh secret list | grep VAULT

# Workflow dispatch (no prompts)
gh workflow run deploy-immutable-ephemeral.yml \
  -f inventory_file='ansible/inventory/staging' \
  -f vault_secret_path='secret/data/runnercloud/deploy-ssh-key'

# Monitor run (non-interactive)
gh run list --workflow=deploy-immutable-ephemeral.yml
```

## Deployment Workflow

The `deploy-immutable-ephemeral.yml` workflow enforces all four principles:

1. **Preflight** job: Validates syntax and hardening rules
2. **Deploy** job: Runs the playbook (with Vault auth)
3. **Idempotence verification**: Second pass in check mode (no changes expected)
4. **Service verification**: Confirms deployment succeeded
5. **Metrics verification**: Checklist for post-deployment monitoring

### To dispatch a deployment:

```bash
gh workflow run deploy-immutable-ephemeral.yml \
  --ref main \
  -f inventory_file='ansible/inventory/staging' \
  -f vault_secret_path='secret/data/runnercloud/deploy-ssh-key' \
  -f ansible_user='deploy' \
  -f dry_run='false' \
  -f verify_idempotence='true'
```

### Inputs:
- `inventory_file`: Ansible inventory (default: `ansible/inventory/staging`)
- `vault_secret_path`: Path in Vault to deploy SSH key (default: `secret/data/runnercloud/deploy-ssh-key`)
- `ansible_user`: SSH user for Ansible (default: `deploy`)
- `dry_run`: Check mode only (`true` or `false`, default: `false`)
- `verify_idempotence`: Run second pass to verify idempotence (default: `true`)

## Configuration Checklist

Before running the workflow, ensure:

- [ ] GitHub repository secrets are set:
  - `VAULT_ADDR`: Vault server URL
  - `VAULT_ROLE_ID`: AppRole Role ID
  - `VAULT_SECRET_ID`: AppRole Secret ID
- [ ] Vault secret exists at `secret/data/runnercloud/deploy-ssh-key` with `private_key` field
- [ ] Target inventory file exists (e.g., `ansible/inventory/staging`)
- [ ] Ansible playbook is syntatically correct (preflight will validate)
- [ ] Systemd unit templates include hardening directives

## Post-Deployment Verification

After a successful deployment, verify:

1. **Service Status**:
   ```bash
   systemctl status vault-integration.service
   ```

2. **Immutability**:
   ```bash
   ls -l /usr/libexec/vault-integration*   # mode 0555
   systemctl cat vault-integration.service | grep ProtectSystem
   ```

3. **Ephemerality**:
   ```bash
   mount | grep /run/vault-credentials
   df -h /run
   ```

4. **Metrics**:
   ```bash
   curl -s http://localhost:9091/metrics | grep runner_rotation
   ```

## Troubleshooting

**Deployment failed during Vault auth**:
- Check repo secrets: `gh secret list | grep VAULT`
- Verify Vault server is reachable: `curl http://$VAULT_ADDR/v1/sys/health`

**Idempotence check failed (second pass showed changes)**:
- Review Ansible playbook for non-idempotent tasks (e.g., shell scripts without guards)
- Run locally to debug: `ansible-playbook --check ansible/playbooks/deploy-rotation.yml`

**Service failed to start**:
- Check systemd logs: `journalctl -u vault-integration.service -n 50`
- Verify permissions and paths: `ls -la /usr/libexec/vault-integration*`

## Related Issues & PRs

- Issue #711: Initiative to make build immutable/ephemeral/idempotent
- PR #708: Deploy workflow with Vault integration
- PR #711: Preflight CI and hardening checks
- Workflow: `.github/workflows/deploy-immutable-ephemeral.yml`

## Next Steps

- [ ] Run a test deployment in staging
- [ ] Configure Prometheus alerting for `runner_rotation_failures`
- [ ] Document runbooks for common operational tasks
- [ ] Implement automated rollback on metric thresholds
