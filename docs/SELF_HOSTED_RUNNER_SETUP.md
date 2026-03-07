Self-hosted GitHub Actions Runner Setup (On-prem / Sovereign)

Overview
- This document explains how to provision a GitHub Actions self-hosted runner on your infrastructure and run Actions jobs without relying on GitHub-hosted runners.

Prerequisites
- Machine with Linux (systemd recommended), Docker optional
- Network access to GitHub (api.github.com)
- A GitHub repo (or org) admin token to create registration tokens

Quick Steps (automated)
1. Obtain a registration token:

```bash
# Repo-level token (expires 1 minute) - run as a user with repo admin
gh api --method POST /repos/:owner/:repo/actions/runners/registration-token --jq .token
```

2. Run the installer on your host (example):

```bash
# on the host that will be the runner
sudo mkdir -p /opt/actions-runner
cd /opt/actions-runner
# on this machine (copy a token produced above):
/scripts/ci/setup-self-hosted-runner.sh https://github.com/OWNER/REPO my-runner "<TOKEN>" /opt/actions-runner
```

3. The script configures and registers the runner and installs a systemd service. Verify with:

```bash
sudo systemctl status actions.runner.OWNER-REPO.my-runner.service
```

Notes and security
- Store registration tokens in a secure vault; tokens are short-lived and must be generated per-runner registration. The installer script (`scripts/ci/setup-self-hosted-runner.sh`) already supports fetching the token from Vault when the special value `-` is passed as the token parameter. Provide the Vault path in the `VAULT_SECRET_PATH` environment variable or as the fifth argument. Tokens should be rotated regularly and revoked immediately if a runner host is compromised.
- A CI check (`.github/workflows/governance-checks.yml`) now scans for accidental token commits and other secrets.
- Use the `actions-runner-controller` if you prefer Kubernetes-managed runners with autoscaling via KEDA.
- Tighten runner host security and restrict which repos/orgs are allowed to use the runner in GitHub repository settings.

Systemd unit template
- A template is provided at `scripts/ci/runner.service.template` which can be adjusted to match your user and paths.

If you want, I can:
- Add a `systemd` unit file generator and a `kubernetes` manifest for actions-runner-controller.
- Create a small Ansible playbook to provision a fleet of runners.

## Recommended Labels
- `self-hosted` (required)
- `linux` (for Linux hosts)
- `self-hosted-heavy` (for heavy CI jobs that run Docker/kind/Buildx/Terraform)
- `x86_64` or `arm64` (optional, if using mixed architectures)

## Required Software (for `self-hosted-heavy`)
- Docker and Buildx
- kind (or k3d) for local Kubernetes clusters
- Terraform >= 1.5.x
- kubectl
- helm
- jq, unzip, curl

Use the in-repo installer scripts under `ci/scripts/` (for example `setup-buildx.sh`, `setup-kind.sh`, `setup-terraform.sh`, `setup-kubectl.sh`) to automate idempotent installation of these tools.

## Recommended Sizing (self-hosted-heavy)
- CPU: 8+ cores
- Memory: 32GB+
- Disk: 100GB+ (SSD recommended)

For lightweight runners a smaller VM (2 CPU / 8GB RAM) is usually sufficient.

## Verification Checklist
1. Ensure the runner appears in GitHub and reports labels: `self-hosted`, `linux`, and `self-hosted-heavy`.
2. Run a smoke workflow that checks:
	- `docker version` and `docker buildx version`
	- `kind create cluster --name smoke` (then `kind delete cluster --name smoke`)
	- `terraform version`
	- `kubectl version --client`
3. Confirm workflows targeting `runs-on: [self-hosted, linux, self-hosted-heavy]` run on the host.

## Autoscaling and Pooling
- For bursty workloads consider a small autoscaling pool (VM scale set, MIG, or runner-controller).
- For predictable heavy workloads, dedicate one or more `self-hosted-heavy` machines.

## Next Steps
- Optionally add a smoke workflow in `.github/workflows/` that performs the verification checklist above. I can create a PR for that if you'd like.

