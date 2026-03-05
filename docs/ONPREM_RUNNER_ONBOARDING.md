# On-Prem Self-Hosted Runner Onboarding (Quick Runbook)

This runbook describes minimal safe steps to provision and register an on-prem GitHub Actions self-hosted runner host. Use for Ops handoff or manual onboarding.

Prerequisites
- Host (Linux) with outbound HTTPS access to github.com:443
- SSH access as `admin` (or equivalent) to the host
- GitHub repo/org admin privileges to create registration tokens
- Vault or secure secret store recommended

1) Provision host
- Prepare a Linux VM (Ubuntu 22.04 recommended) with required packages:
  - `curl`, `tar`, `jq`, `unzip`, `ca-certificates`
- Allocate sufficient disk: 50+ GB for build workloads
- Ensure time sync: `sudo apt install -y chrony && sudo systemctl enable --now chrony`

2) Create a registration token (short-lived)
- In GitHub: Settings → Actions → Runners → New self-hosted runner → Generate token
- Or via CLI (personal access token with repo:admin:org scope):
  ```bash
  gh api -X POST /repos/:owner/:repo/actions/runners/registration-token
  ```
- Store the token securely (Vault, or ephemeral env var)

3) Download & configure runner
- On host as `admin`:
  ```bash
  mkdir -p ~/actions-runner && cd ~/actions-runner
  # fetch appropriate runner binary (example x64)
  curl -fsSL -o actions-runner.tar.gz https://github.com/actions/runner/releases/download/v2.332.0/actions-runner-linux-x64-2.332.0.tar.gz
  tar xzf actions-runner.tar.gz
  ./config.sh --url https://github.com/<owner>/<repo> --token $RUNNER_TOKEN --name "onprem-$(hostname)" --labels "self-hosted,on-prem,linux" --work _work
  sudo ./svc.sh install
  sudo ./svc.sh start
  ```
- Verify runner appears in GitHub: Settings → Actions → Runners

4) Secure token & secrets
- Do NOT commit tokens to repo
- Prefer storing `RUNNER_TOKEN` in Vault and using a short-lived fetch during startup
- Example (systemd unit or startup script) reads token from Vault and registers at boot

5) System integration & autoscaling
- Register monitoring: Prometheus node exporter or Datadog agent
- Configure log rotation for `/var/log/actions-runner/_diag`
- If using Kubernetes or K8s-managed runners, consider `actions-runner-controller`

6) Health checks and validation
- Run quick job against the runner by creating a test workflow referencing the runner label:
  ```yaml
  on: [push]
  jobs:
    test-onprem:
      runs-on: [self-hosted, on-prem, linux]
      steps:
        - run: echo "runner ok"
  ```
- Verify job completes on the intended runner and artifacts/logs are available

7) Decommission / rotation
- To unregister a runner:
  ```bash
  sudo ./svc.sh stop
  sudo ./svc.sh uninstall
  ./config.sh remove --token $RUNNER_TOKEN
  ```
- Rotate tokens regularly and remove unreachable runners from GitHub UI

8) Troubleshooting
- Check runner service status: `sudo systemctl status actions.runner.*` (or `sudo ./svc.sh status`)
- Check runner diag logs: `tail -n 200 _diag/*`
- If runner fails to start, verify connectivity to `https://github.com` and token validity

Files & helpers in repo
- `scripts/ci/setup-self-hosted-runner.sh` — helper script to bootstrap a runner (review & adapt)
- `scripts/fetch-runner-binaries.sh` — fetches runner binaries at runtime (used to avoid committing large binaries)
- Docs: `docs/RUNNER_INFRASTRUCTURE_DEPLOYMENT.md` — infra-level deployment guide

If you want, I can:
- Add a small `systemd` unit template and token fetch helper in `scripts/`.
- Create a one-click provisioning script that registers the runner using Vault secrets.
