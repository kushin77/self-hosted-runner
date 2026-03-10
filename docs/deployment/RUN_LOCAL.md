Phase 3B Local Runner — Installation & Usage

Overview
- This repository includes a local runner and systemd units to run Phase 3B provisioning
  without GitHub Actions.
- The runner executes `scripts/phase3b-credentials-aws-vault.sh` and appends an
  immutable JSONL audit entry to `logs/deployment-provisioning-audit.jsonl`.

Files added
- `runners/phase3b-local-runner.sh` — runner script (idempotent, logs audit)
- `systemd/phase3b-local-runner.service` — systemd service unit (oneshot)
- `systemd/phase3b-local-runner.timer` — systemd timer (daily 02:00 UTC)

Prerequisites
- `bash`, `jq`, `vault`/`aws`/`gcloud` CLIs (as required by provisioning script)
- `VAULT_ADDR`, `VAULT_NAMESPACE` and other secrets should be provided via environment
  or a secure file readable only by the runner user. Do NOT store secrets in repo.

Install (as root or admin)

1. Copy systemd unit files to `/etc/systemd/system`:

```bash
sudo cp systemd/phase3b-local-runner.service /etc/systemd/system/
sudo cp systemd/phase3b-local-runner.timer /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/phase3b-local-runner.*
```

2. Enable and start the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now phase3b-local-runner.timer
sudo systemctl status phase3b-local-runner.timer --no-pager
```

3. Manual run (for testing):

```bash
# As the configured runner user (or root if necessary)
bash runners/phase3b-local-runner.sh
# Or via systemd
sudo systemctl start phase3b-local-runner.service
sudo journalctl -u phase3b-local-runner.service --no-pager
```

Logs & Audit
- Run log files are written to `logs/` as `deployment-provisioning-<timestamp>.log`.
- Immutable audit entries are appended to `logs/deployment-provisioning-audit.jsonl`.

Notes on security & idempotence
- The runner is designed to be idempotent; the underlying provisioning script must
  also be idempotent (it already is in this repo).
- Provide credentials via a secure mechanism (GSM, Vault, KMS) and set environment
  variables in a secure profile for the `User` configured in the systemd unit.

If you prefer cron instead of systemd, use `crontab -e` and add a line:

```cron
0 2 * * * /usr/bin/env bash /home/akushnir/self-hosted-runner/runners/phase3b-local-runner.sh >> /home/akushnir/self-hosted-runner/logs/cron-phase3b.log 2>&1
```
