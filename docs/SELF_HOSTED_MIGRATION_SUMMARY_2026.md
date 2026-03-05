# Self-Hosted Runner Migration Complete (2026-03-05)

The repository has been successfully migrated from GitHub-hosted `ubuntu-latest` runners to a localized self-hosted infrastructure. This ensures sovereignty over CI/CD pipelines, reduces billing overhead, and provides a stable environment for production workloads.

## Key Changes
- **Workflow Updates**: All YAML files in `.github/workflows` now use `runs-on: [self-hosted, linux]`.
- **Runner Activation**: A self-hosted runner process (`actions-runner`) is active on the infrastructure node, labeled correctly to pick up all repository jobs.
- **Service Stability**: The runner is currently running as a managed background process with logging to `/tmp/runner.log`.

## Operations Guide
To manage the runner on the host:
- **Check Status**: `ps aux | grep Runner.Listener`
- **View Logs**: `tail -f /tmp/runner.log`
- **Restart**:
  ```bash
  cd ~/self-hosted-runner/actions-runner
  ./run.sh
  ```

## Repository Rules & Governance
- **Labeling Policy**: All new workflows MUST use `runs-on: [self-hosted, linux]`. GitHub-hosted runners are deprecated for this repository.
- **Secrets Management**: Runner-level secrets should be managed via GitHub Environment secrets or fetched dynamically from the integrated Vault instance.
- **Maintenance**: Ensure the runner software is updated periodically via the `actions-runner` directory.

## Success Verification
- Verified jobs such as `validate-dashboard` and `full-airgap-test` have transitioned to the local runner.
- Multiple tracking issues (#385, #374, #363, #362, #342) have been closed as resolved.
