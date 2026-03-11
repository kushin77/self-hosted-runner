# Audit aggregation and scheduling

This folder provides tools to aggregate secret mirroring audit logs and schedule regular aggregation.

Files:
- `tools/audit-aggregate.sh` — merges `logs/secret-mirror/mirror-*.jsonl` into a single aggregate file and optionally signs it with GPG when `GPG_KEY` is set.
- `tools/install-audit-timer.sh` — installer script to create a systemd unit and timer that runs the aggregation daily (requires `sudo`).
- `tools/systemd/*.tmpl` — systemd unit and timer templates used by the installer.

Install (run as root):

```bash
sudo tools/install-audit-timer.sh
```

Verify:

```bash
systemctl status audit-aggregate.timer
journalctl -u audit-aggregate.service --no-pager
```

Notes:
- This setup is operator-managed (direct deployment) — no GitHub Actions or PRs.
- If you want KMS-based signing instead of GPG, modify `tools/audit-aggregate.sh` to call your KMS sign command and place the signature alongside the aggregate file.
