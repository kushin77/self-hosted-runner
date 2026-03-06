Self-hosted runners: labels and guidance
=====================================

This repository uses self-hosted GitHub Actions runners for CI workloads.

Recommended runner labels to use in workflows:
- `self-hosted` (required label)
- `linux` (OS tag)
- `x86_64` or `arm64` (optional architecture tag)
- `ci` or `runner` (optional logical grouping)

Examples
--------

Use in workflows:

```yaml
runs-on: [self-hosted, linux]
```

Notes
-----
- Make sure your self-hosted runners are online and healthy before enabling frequent CI runs.
- For heavyweight jobs (docker/kind/terraform) ensure runners have Docker and required tools installed, or use a dedicated runner label such as `self-hosted-heavy` and reference it in workflows:

```yaml
runs-on: [self-hosted, linux, self-hosted-heavy]
```

- The repository currently expects `linux` runners; if you use other OSes update relevant workflows.

Heavy runner guidance
---------------------

Use `self-hosted-heavy` for runners prepared with:
- Docker / Buildx
- kind or k3d
- Terraform and cloud CLIs
- Sufficient disk, CPU and memory (recommended: 8+ CPUs, 32GB RAM, 100GB disk)

Mark one or more of your self-hosted hosts with labels `self-hosted`, `linux`, and `self-hosted-heavy` so heavy CI jobs are scheduled only on capable machines.
# Self-hosted Runners — Setup & Requirements

This document describes the minimal configuration and labels expected by repository workflows.

Required runner labels (workflows target these):
- `self-hosted`
- `linux`
- `x64`

Recommended additional label(s):
- `runner-type=ci` (useful to route heavier CI jobs to dedicated machines)

Minimal host requirements
- Ubuntu 20.04+ or equivalent Linux distribution
- Docker (optional, required by integration jobs)
- Node.js 20.x and npm
- git + curl
- At least 4 CPU cores and 8GB RAM (adjust for heavy workloads)

Security & secrets
- Register the runner using a short-lived registration token and place it under a restricted service account.
- Ensure repository secrets used by workflows (e.g., `AWS_ROLE_TO_ASSUME`, `ADMIN_API_KEY`) are added to the repo/org secrets.

Service & maintenance
- Run the official GitHub Actions Runner as a service for persistent CI.
- For ephemeral/self-destruct runners (spot instances) use automation to register/unregister on boot/shutdown.

Smoke test
1. Commit the smoke workflow at `.github/workflows/self-hosted-runner-smoke.yml`
2. Dispatch the workflow manually to verify the runner picks up the job.

If you'd like, I can add a runbook with sample `systemd` unit and bootstrap scripts.
