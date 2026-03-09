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

Once the key is installed, you have two choices:

**A. Automatic trigger (preferred):**
- Reply on [Issue #787](https://github.com/kushin77/self-hosted-runner/issues/787) with the exact phrase: `key-installed`
- I will detect this reply and immediately dispatch the `legacy-node-cleanup` workflow, monitor it to completion, and close the issue upon success.

**B. Manual workflow dispatch (if automatic trigger fails):**
- Ensure the key is installed on the legacy host.
- Manually dispatch the workflow via GitHub CLI:
  ```bash
  gh workflow run legacy-node-cleanup.yml --ref main --field confirm=CLEANUP_LEGACY_NODE
  ```
- Or trigger via GitHub UI: https://github.com/kushin77/self-hosted-runner/actions/workflows/legacy-node-cleanup.yml → "Run workflow"

## Branch Management (Issue: automation agent help-wanted)

Several automation branches were created and pushed during the CI/CD automation initiative. See the linked help issue for a list of branches that may require manual review or approval before PR merge.

Status:
- Draft issues created for most automation branches ✓
- Some branches have diverged histories — manual rebase/resolution recommended
- Help issue created with branch list and recommended actions

## Automation Pipeline Summary

| Automation | Status | Trigger | Location |
|-----------|--------|---------|----------|
| Terraform Validation | ✓ Complete | Manual dispatch | `.github/workflows/terraform-validate-dispatch.yml` |
| MinIO Local Smoke Test | ✓ Complete | Manual dispatch | `.github/workflows/minio-local-validate.yml` |
| Stale Branch Cleanup | ✓ Complete | Manual dispatch | `.github/workflows/stale-branch-cleanup.yml` |
| Legacy Node Cleanup | ⏳ Blocked on SSH key | Manual dispatch + confirmation | `.github/workflows/legacy-node-cleanup.yml` |

## Key Files

- **Deploy Public Key**: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG+vqHubKjpwPpBHIeFFmuFiNaAaw2yHvjFd4yFDZHkt deploy-key-automated-20260306`
- **Helper Script**: `scripts/automation/legacy/install_deploy_key.sh`
- **Terraform Validation Helper**: `scripts/automation/terraform/validate_all.sh`
- **MinIO Local Test Helper**: `scripts/automation/minio/local_minio_validate.sh`

## Issues & Tracking

- [Issue #787](https://github.com/kushin77/self-hosted-runner/issues/787) — Legacy Node Cleanup (awaiting SSH key install)
- [Automation agent help-wanted](https://github.com/kushin77/self-hosted-runner/issues) — Branches needing manual review

## Questions?

Post on the relevant issue or reach out to the automation agent (will monitor Issue #787 for `key-installed` confirmation).
