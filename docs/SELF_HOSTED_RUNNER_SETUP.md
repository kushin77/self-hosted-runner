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
- Store registration tokens in a secure vault; tokens are short-lived and must be generated per-runner registration.
- Use the `actions-runner-controller` if you prefer Kubernetes-managed runners with autoscaling via KEDA.
- Tighten runner host security and restrict which repos/orgs are allowed to use the runner in GitHub repository settings.

Systemd unit template
- A template is provided at `scripts/ci/runner.service.template` which can be adjusted to match your user and paths.

If you want, I can:
- Add a `systemd` unit file generator and a `kubernetes` manifest for actions-runner-controller.
- Create a small Ansible playbook to provision a fleet of runners.
