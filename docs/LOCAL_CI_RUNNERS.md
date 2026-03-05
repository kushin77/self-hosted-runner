Local CI / Actions Run Options (Sovereign)
=========================================

Purpose
- Run CI/workflow steps locally or on your own infrastructure instead of GitHub-hosted Actions.

Options
- `act` (nektos/act): run GitHub Actions workflows locally using Docker. Quick for testing but some actions may not be supported.
- Self-hosted runners: Install GitHub Actions Runner on your own machines. Workflows still execute via GitHub but jobs run on your infrastructure.
- actions-runner-controller: Run runners in Kubernetes and manage scale with KEDA. Good for cluster-based sovereignty.
- Convert workflows to local scripts: create idempotent shell scripts that perform CI steps (recommended for full sovereignty).

Recommended approach for full sovereignty
1. Create local runnable scripts for critical tasks (plan/apply/test). See `scripts/local/run-plan.sh` and `scripts/local/run-apply.sh`.
2. Store secrets in your own Vault/Secrets Manager and inject into runner environment at runtime.
3. Use actions-runner-controller on your Kubernetes cluster to host runners that pull jobs from GitHub but run on-prem. Or run `act` on a CI host to execute workflows locally.

Quick start examples

Run Terraform plan locally (recommended):
```
scripts/local/run-plan.sh
```

Apply the plan locally (requires valid credentials and `tfplan`):
```
scripts/local/run-apply.sh
```

Running workflows with `act` (developer/test):
1. Install `act` (https://github.com/nektos/act)
2. Export any required secrets locally:
```
export AWS_ROLE_TO_ASSUME="arn:aws:iam::123456789012:role/CI-Terraform-Role"
export AWS_REGION="us-east-1"
```
3. Run the workflow:
```
act -j "Terraform Plan (aws-spot)" -P ubuntu-latest=nektos/act-environments-ubuntu:18.04
```

Notes and caveats
- `act` emulates Actions but doesn't support every marketplace action and has networking/storage differences.
- For production deployments prefer self-hosted runners or actions-runner-controller on your infrastructure.
- Secure your secrets: do not hardcode them in repo. Use Vault or environment injection on runner hosts.

If you want, I can:
- Add `systemd` unit or Kubernetes manifest to run a self-hosted runner manager.
- Convert the GitHub workflows into self-contained runner scripts and add a small orchestrator.
