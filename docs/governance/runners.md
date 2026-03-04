# ElevatedIQ CI Runner Governance
# NIST-AC-2: Account Management | NIST-IA-2: Identification and Authentication

## Overview
ElevatedIQ uses a hybrid CI approach. Standard builds run on GitHub-hosted and Cloud Build runners. Memory-intensive jobs (RCA, large container builds, full integration tests) are routed to **High-Memory Self-Hosted Runners**.

## Runner Tiers

| Label | Specs | Primary Use Case |
|-------|-------|------------------|
| `ubuntu-latest` | 2 vCPU, 7GB RAM | Linting, small unit tests |
| `high-mem` | 4 vCPU, 32GB+ RAM | Docker builds, RCA Graph, Heavy Tests |

## Provisioning
Runners are provisioned via Terraform in the `terraform/modules/ci-runners` directory.

### To add a new runner:
1. Generate a runner registration token in GitHub Repository Settings.
2. Add the token to the `runner_tokens` list in your `terraform.tfvars`.
3. Apply changes:
   ```bash
   cd terraform
   terraform apply
   ```

## Security Standards
1. **Zero-Trust**: Runners are isolated in a restricted VPC.
2. **Short-Lived Tokens**: Registration tokens must be cycled every 24 hours (automated).
3. **Ephemeral Storage**: SSD storage is wiped after each build completion.
4. **Audit Logging**: All shell commands on the runner are streamed to Cloud Logging.

## Usage in Workflows
To use a high-memory runner, update your workflow YAML:

```yaml
jobs:
  heavy-task:
    runs-on: [self-hosted, high-mem]
    steps:
      - uses: actions/checkout@v4
      # steps here...
```

  ## Runner Hygiene: Stale Pytest Protection

  To prevent orphan long-lived `pytest` processes from leaving runners in a false busy state:

  - Scheduled watchdog workflow: `.github/workflows/runner-pytest-hygiene.yml`
  - Watchdog script: `scripts/automation/pmo/runner_pytest_hygiene.sh`
  - Per-job PID guard wrapper: `scripts/automation/pmo/pytest_job_guard.sh`

  ### What this enforces

  1. Periodic stale-process cleanup (default threshold: 7200s)
  2. Per-job pytest PID tracking and teardown guard for cancellation/failure
  3. Alert issue creation when stale processes are detected
  4. Preflight hygiene baseline before required pytest checks

  ## Safe Recovery and Requeue Runbook

  When checks remain queued/in-progress and the `.42` runner appears busy:

  1. Verify stale pytest state on `.42`
    ```bash
    ssh akushnir@192.168.168.42 "cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo && ./scripts/automation/pmo/runner_pytest_hygiene.sh --report --threshold-seconds 900"
    ```
  2. Clean stale pytest process trees (TERM then KILL fallback)
    ```bash
    ssh akushnir@192.168.168.42 "cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo && ./scripts/automation/pmo/runner_pytest_hygiene.sh --cleanup --threshold-seconds 900"
    ```
  3. Validate clean baseline before accepting new jobs
    ```bash
    ssh akushnir@192.168.168.42 "cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo && ./scripts/automation/pmo/runner_pytest_hygiene.sh --strict --threshold-seconds 900"
    ```
  4. If runner still reports busy, restart runner service on `.42`
    ```bash
    ssh akushnir@192.168.168.42 "sudo systemctl restart actions-runner && sudo systemctl status actions-runner --no-pager | head -20"
    ```
  5. Requeue the failed/canceled workflow from GitHub Actions UI (or rerun failed jobs)

  NIST mapping: SI-4 (monitoring), CM-3 (configuration control), AU-2 (audit evidence).

## Secondary Runner Managed Service Runbook (.42)

Runner identity:
- Name: `dev-elevatediq-fullstack-2`
- Install path: `/home/akushnir/actions-runner-2`
- Service unit: `actions.runner.kushin77-ElevatedIQ-Mono-Repo.dev-elevatediq-fullstack-2.service`
- Required labels: `fullstack`, `high-mem` (plus `required-gates`)

### Health checks

```bash
ssh akushnir@192.168.168.42 "sudo systemctl status actions.runner.kushin77-ElevatedIQ-Mono-Repo.dev-elevatediq-fullstack-2.service --no-pager -l | head -40"
ssh akushnir@192.168.168.42 "sudo systemctl is-enabled actions.runner.kushin77-ElevatedIQ-Mono-Repo.dev-elevatediq-fullstack-2.service"
gh api repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners --jq '.runners[] | select(.name==\"dev-elevatediq-fullstack-2\") | {status,busy,labels:[.labels[].name]}'
```

### Recovery

```bash
ssh akushnir@192.168.168.42 "sudo systemctl restart actions.runner.kushin77-ElevatedIQ-Mono-Repo.dev-elevatediq-fullstack-2.service"
ssh akushnir@192.168.168.42 "sudo journalctl -u actions.runner.kushin77-ElevatedIQ-Mono-Repo.dev-elevatediq-fullstack-2.service -n 80 --no-pager"
```

If custom labels drift, re-apply:

```bash
gh api -X POST repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners/22/labels -f labels[]=fullstack -f labels[]=high-mem -f labels[]=required-gates
```
