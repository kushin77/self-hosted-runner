# Hardened Self-Hosted Runner — Onboarding Runbook

Purpose
-------
Guide to provision and harden a self-hosted runner that will execute the chaos test orchestrator and scheduled cron jobs.

Prerequisites
-------------
- Linux host (Debian/Ubuntu recommended)
- Minimal network access; outgoing to artifact/upload endpoints only
- Access to GSM/Vault/KMS for credential retrieval

Steps
-----
1. Create a dedicated system user:

```bash
sudo useradd -m -s /bin/bash runner
sudo mkdir -p /opt/runner
sudo chown runner:runner /opt/runner
```

2. Install required tooling:

```bash
sudo apt-get update
sudo apt-get install -y git bash coreutils awscli unzip
```

3. Deploy code and scripts:

```bash
sudo -u runner git clone https://github.com/kushin77/self-hosted-runner /opt/runner/repo
cd /opt/runner/repo
```

4. Configure credential retrieval (GSM → Vault → KMS):
- Use short-lived credentials fetched at runtime. See `scripts/ops/upload_jsonl_to_s3.sh` for examples.

5. Create a systemd unit for the runner cron wrapper (optional):

```ini
[Unit]
Description=Chaos Orchestrator Runner

[Service]
Type=simple
User=runner
WorkingDirectory=/opt/runner/repo
ExecStart=/bin/bash -lc '/opt/runner/repo/scripts/testing/run-all-chaos-tests.sh'

[Install]
WantedBy=multi-user.target
```

6. Lock down host:
- Disable password-based SSH for the `runner` user.
- Restrict sudo to explicit commands only.
- Enable automatic security updates.

Monitoring & Logging
--------------------
- Forward logs to a secure log collector. Archive JSONL artifacts using the uploader script to immutable storage.

Rollback and Emergency Stop
---------------------------
- To stop scheduled runs: disable cron entry or stop the systemd service.
- To revoke access: rotate credentials in GSM/Vault and revoke runner keys.

Notes
-----
- Runner must operate under least privilege.
- Do not enable GitHub Actions in repo settings — policy enforced in `POLICIES/NO_GITHUB_ACTIONS.md`.
