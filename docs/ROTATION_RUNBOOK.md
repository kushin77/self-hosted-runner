# Runner Rotation Runbook

Purpose
- Automate periodic rotation of self-hosted GitHub Actions runners by obtaining fresh registration tokens from Vault and re-registering runners.

Components
- `scripts/ci/rotate-runner.sh` — rotates a single runner (remove + re-register).
- `scripts/ci/auto_rotate_runners.sh` — iterate a config of runners and call `rotate-runner.sh` for each.
- `scripts/ci/rotate-runner.service.template` and `rotate-runner.timer.template` — systemd service/timer templates to schedule runs.

Setup (high level)
1. Place a config file at `/etc/actions-runner/rotation.conf` with CSV lines:
   /opt/actions-runner,https://github.com/owner/repo,runner-name,secret/data/ci/self-hosted/runner-name
2. Optionally create `/etc/default/rotate-runners` with `VAULT_ADDR` and `DRY=1` for testing.
3. Install `auto_rotate_runners.sh` into `/usr/local/bin/` and make it executable.
4. Install the systemd service and timer (see templates) and enable the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now auto-rotate-runners.timer
```

Operational notes
- Start with `DRY=1` to test behavior; inspect logs via `journalctl -u auto-rotate-runners.service`.
- The rotation script attempts a best-effort `config.sh remove` before re-registering. If removal requires a different token, the runner can be removed manually from the repo settings.
- Schedule frequency: start weekly or daily depending on security requirements.

Rollback
- If rotation fails, logs will show which runner failed. You can revert by re-registering the runner manually using `scripts/ci/setup-self-hosted-runner.sh` with a valid token.

Security
- Ensure Vault access is limited to the roles/policies required. Use short-lived Vault client tokens via OIDC.
- Avoid logging tokens. The scripts are designed to avoid printing tokens to stdout.

Next steps
- Integrate the rotation setup into Terraform `user_data` for automated deployment.
- Add alerting for repeated rotation failures (Prometheus alert + PagerDuty).
