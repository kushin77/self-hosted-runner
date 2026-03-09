---
title: Deploy Key Installation Remediation — Hands-Off Automation Runbook
date: 2026-03-07
status: Production Ready
version: 1.0
---

# Deploy Key Installation Remediation — Hands-Off Automation Runbook

## Overview

This runbook documents the fully automated, idempotent deploy key installation system for the self-hosted runner infrastructure. The system is designed for **hands-off operations** with immutable, ephemeral, idempotent workflows and safe dry-run validation by default.

## System Architecture

### Components

| Component | Purpose | Status |
|-----------|---------|--------|
| `run-install-deploy-key.yml` | Main remediation workflow | ✅ Production Ready |
| `ansible/playbooks/install-deploy-key.yml` | Idempotent key installation | ✅ Idempotent & Validated |
| `ansible/inventory/staging` | Target inventory (localhost) | ✅ CI/CD Compatible |
| `.github/actions/resilience-loader` | Retry helpers & resilience | ✅ Fixed & Deployed |
| `.github/scripts/resilience.sh` | Bash helpers for retries | ✅ Available |

### Design Principles

- **Immutable**: All changes via code + Draft issues (no manual operations in runners)
- **Ephemeral**: Workflow generates temporary test keys on-demand; no persistent state
- **Idempotent**: Safe to re-run; operations are repeatable without side effects
- **Noop-Safe**: Default is dry-run (check mode); apply mode optional
- **Fully Automated**: Dispatch via `workflow_dispatch`; no manual SSH or CLI needed

## Deployment Modes

### 1. Dry-Run Validation (Default)

```bash
gh workflow run run-install-deploy-key.yml \
  --repo kushin77/self-hosted-runner \
  --ref main
```

**Behavior:**
- Generates test SSH keypair (idempotent; reuses if exists)
- Runs Ansible in `--check` mode (read-only validation)
- Reports tasks that would be executed
- **No changes applied to targets**

**Expected Output:**
- ✅ Gathers facts from target
- ✅ Ensures deploy user exists (check mode)
- ✅ Validates authorized_keys installation (check mode)
- ✅ No errors → workflow succeeds

### 2. Apply Mode (Manual Approval)

```bash
gh workflow run run-install-deploy-key.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f dry_run=false
```

**Prerequisites:**
- Either `DEPLOY_SSH_KEY` repository secret (deploy public key), OR
- Vault credentials: `VAULT_ROLE_ID` + `VAULT_SECRET_ID`

**Behavior:**
- Uses provided deploy public key (or fetches from Vault)
- Runs Ansible in apply mode (executes tasks)
- **Installs deploy key into target's authorized_keys**
- Runs idempotently: subsequent runs confirm key exists

**Safety Checks:**
- Playbook always includes become: true
- SSH key is securely cleaned up after workflow
- Inventory restricted to localhost by default

## Operational Procedures

### Running a Dry-Run Validation

1. **Dispatch the workflow:**
   ```bash
   gh workflow run run-install-deploy-key.yml --repo kushin77/self-hosted-runner --ref main
   ```

2. **Monitor run status:**
   ```bash
   gh run list --workflow run-install-deploy-key.yml --repo kushin77/self-hosted-runner --limit 1
   ```

3. **View logs (if needed):**
   ```bash
   gh run view <run-id> --repo kushin77/self-hosted-runner --log
   ```

4. **Expected success indicators:**
   - `Gathering Facts` → OK
   - `Ensure deploy user exists` → OK or OK (changed)
   - `Install public key into authorized_keys` → OK or OK (changed)
   - `PLAY RECAP` → `failed=0`

### Running Apply Mode (Production)

**Before running apply mode, ensure:**

1. **Provide deploy SSH public key** (choose one method):

   Method A: Store as repository secret
   ```bash
   gh secret set DEPLOY_SSH_KEY --repo kushin77/self-hosted-runner < /path/to/deploy_id_rsa.pub
   ```

   Method B: Use Vault AppRole (recommended for CI/CD)
   ```bash
   gh secret set VAULT_ROLE_ID --repo kushin77/self-hosted-runner --body "your-role-id"
   gh secret set VAULT_SECRET_ID --repo kushin77/self-hosted-runner --body "your-secret-id"
   ```

2. **Dispatch in apply mode:**
   ```bash
   gh workflow run run-install-deploy-key.yml \
     --repo kushin77/self-hosted-runner \
     --ref main \
     -f dry_run=false
   ```

3. **Monitor execution** (same as dry-run; look for `changed=1` in relevant tasks)

4. **Verify on target:**
   ```bash
   # SSH to target runner as deploy user
   ssh deploy@<runner-host>
   cat ~/.ssh/authorized_keys | grep "test-deploy-key-"  # Verify key is installed
   exit
   ```

### Custom Inventory (Advanced)

To target a different inventory or change the ansible user:

```bash
gh workflow run run-install-deploy-key.yml \
  --repo kushin77/self-hosted-runner \
  --ref main \
  -f inventory_file="ansible/inventory/production" \
  -f ansible_user="ubuntu" \
  -f dry_run=false
```

## Troubleshooting

### Issue: Workflow fails with "Inventory file not found"

**Cause**: Custom inventory path does not exist

**Fix**: Verify file exists:
```bash
ls -l ansible/inventory/<your-path>
```

Ensure the inventory format is valid YAML and contains at least:
```yaml
[all]
localhost ansible_connection=local
```

### Issue: Ansible task fails with "No deploy public key found"

**Cause**: Neither `DEPLOY_SSH_KEY` repo secret nor Vault credentials provided, and test key generation was skipped

**Fix**: Either:
- Provide `DEPLOY_SSH_KEY` repo secret with your deploy public key, OR
- Provide `VAULT_ROLE_ID` and `VAULT_SECRET_ID` for Vault integration

For dry-run, test key is auto-generated (no action needed).

### Issue: SSH connection timeout to target

**Cause**: Target host is unreachable or firewall is blocking SSH

**Fix**: 
- Verify target is online: `ping <target-ip>`
- Check firewall allows SSH on port 22: `nc -zv <target-ip> 22`
- If using custom inventory, ensure inventory file specifies reachable target

### Issue: Permission denied when installing authorized_keys

**Cause**: Playbook `become: true` but ansible user lacks sudo privileges

**Fix**: Ensure the ansible user has sudo access:
```bash
# On target, as root
usermod -aG sudo <ansible-user>
# Or set up sudoers for password-less sudo:
echo "<ansible-user> ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ansible
```

## Monitoring & Alerts

### Workflow Run Monitoring

```bash
# List last 10 runs
gh run list --workflow run-install-deploy-key.yml --repo kushin77/self-hosted-runner --limit 10 --json number,status,conclusion

# Watch run status in real-time (poll every 10 seconds)
watch -n 10 "gh run list --workflow run-install-deploy-key.yml --repo kushin77/self-hosted-runner --limit 1 --json status,conclusion"
```

### Key Metrics

- **Run Duration**: Typically 30-60 seconds (dry-run); 60-120 seconds (apply mode)
- **Key Task Times**:
  - Gathering Facts: ~5-10 seconds
  - Ensure deploy user exists: ~1-2 seconds
  - Install authorized_keys: ~1-2 seconds

### Success Criteria

✅ **Dry-run successful** when:
- Status: `completed`
- Conclusion: `success`
- PLAY RECAP shows `failed=0` and `unreachable=0`

✅ **Apply-mode successful** when:
- Same as dry-run, PLUS:
- `Install public key into authorized_keys` shows `changed=1` (first run) or `ok` (idempotent subsequent runs)

## Automation Integration

### Scheduled Validation (Optional)

To run dry-run validation automatically (e.g., weekly):

```yaml
# .github/workflows/scheduled-validation.yml
name: Scheduled Deploy Key Validation

on:
  schedule:
    - cron: '0 2 * * 0'  # Every Sunday at 2 AM UTC

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run dry-run validation
        run: |
          gh workflow run run-install-deploy-key.yml \
            --repo kushin77/self-hosted-runner \
            --ref main
```

### Auto-Remediation (Machine-Sealed)

When combined with auto-remediation pipelines, apply-mode can be triggered based on:
- Security findings (missing or expired keys)
- Health check failures
- Operator approval via issue comments

## Governance & Security

### Access Control

- **Who can dispatch**: Repo maintainers + CI/CD automation
- **Who can modify**: Maintainers (Draft issues required)
- **Keys stored**: Repository secrets (encrypted)

### Audit Trail

All workflow runs are logged in GitHub Actions UI with:
- Dispatch time
- Inputs (inventory, user, dry_run flag)
- Execution logs (sanitized of secrets)
- Results (success/failure)

### Secret Management

- **Deploy keys**: Stored as repository secrets (encrypted at rest)
- **Vault credentials**: Never logged; sanitized in workflow output
- **SSH keys**: Generated in `/tmp/`, automatically cleaned up after workflow

## Recovery Procedures

### If Workflow Fails (Apply Mode)

1. **Investigate** the workflow logs for error details
2. **Dry-run the same inputs** to validate the playbook logic
3. **Check target host** status (reachability, disk space, user permissions)
4. **Fix the issue** and re-dispatch apply mode

**Idempotency guarantee**: If the first apply failed mid-task, re-running is safe and will complete successfully.

### If Deployed Key Needs to be Revoked

1. **SSH to target** as authorized user:
   ```bash
   ssh <user>@<target>
   # Remove deployed key from authorized_keys
   nano ~/.ssh/authorized_keys  # or use sed to remove the key
   ```

2. **Verify removal**:
   ```bash
   cat ~/.ssh/authorized_keys | grep -c "test-deploy-key-"  # Should be 0
   ```

3. **If needed, re-run deploy-key workflow** with new key.

## Documentation & Support

- **Workflow Source**: [.github/workflows/run-install-deploy-key.yml](.github/workflows/run-install-deploy-key.yml)
- **Playbook Source**: [ansible/playbooks/install-deploy-key.yml](../../ansible/playbooks/install-deploy-key.yml)
- **Issue Tracking**: [#1265 - Completion Summary](https://github.com/kushin77/self-hosted-runner/issues/1265)
- **Resilience Loader**: [.github/actions/resilience-loader/README.md](../../self_healing/README.md)

### Contact & Questions

For issues or questions:
1. Check this runbook's troubleshooting section
2. Review workflow logs: `gh run view <run-id> --repo kushin77/self-hosted-runner --log`
3. Open an issue in the repository with details

---

**Last Updated**: 2026-03-07  
**Version**: 1.0 (Production Ready)  
**Maintainer**: Automation Team
