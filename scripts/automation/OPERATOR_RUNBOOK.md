# Automation Operator Runbook

This runbook documents the hands-off automation system and operator procedures for the self-hosted-runner repository.

## Overview

The repository has implemented the following fully automated workflows:
- **Terraform Validation** — automated in `.github/workflows/terraform-validate-dispatch.yml`
- **MinIO Local Smoke Tests** — automated in `.github/workflows/minio-local-validate.yml`
- **Stale Branch Cleanup** — completed; 39 merged branches deleted via `.github/workflows/stale-branch-cleanup.yml`
- **Legacy Node Cleanup** — automated in `.github/workflows/legacy-node-cleanup.yml` (blocked on SSH key install)

## Legacy Node Cleanup (Issue #787)

### Current Status
- Workflow is staging on GitHub Actions but cannot execute without SSH access to the legacy host (192.168.168.31).
- Blocker: Deploy public key must be installed on the legacy host for SSH-based automation to proceed.

### To Enable Legacy Cleanup:

#### Option 1: One-line SSH install (recommended)
```bash
ssh <user>@192.168.168.31 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+vqHubKjpwPpBHIeFFmuFiNaAaw2yHvjFd4yFDZHkt deploy-key-automated-20260306" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Replace `<user>` with the target user on the legacy host.

#### Option 2: Use the helper script
From a machine with SSH access to the legacy host, clone this repo and run:
```bash
./scripts/automation/legacy/install_deploy_key.sh <user>@192.168.168.31
```

#### Option 3: Manual install (offline)
1. SSH into 192.168.168.31 as the target user.
2. Create/ensure `~/.ssh` directory with proper permissions:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   ```
3. Add the deploy public key to `~/.ssh/authorized_keys`:
   ```bash
   echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+vqHubKjpwPpBHIeFFmuFiNaAaw2yHvjFd4yFDZHkt deploy-key-automated-20260306" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

### After Installing the Key:

Once the key is installed, reply on [Issue #787](https://github.com/kushin77/self-hosted-runner/issues/787) with:

```
key-installed
```

The system will detect this reply and automatically:
1. Dispatch the legacy-node-cleanup workflow
2. Monitor it to completion
3. Download artifacts and close the issue upon success

## Automation Pipeline Summary

| Automation | Status | Trigger |
|-----------|--------|---------|
| Terraform Validation | ✓ Complete | Manual dispatch |
| MinIO Local Smoke Test | ✓ Complete | Manual dispatch |
| Stale Branch Cleanup | ✓ Complete | Manual dispatch |
| Legacy Node Cleanup | ⏳ Blocked on SSH key | Manual dispatch + confirmation |

## Questions?

Post on Issue #787 or check AUTOMATION_INITIATIVE_COMPLETE.md for details.
