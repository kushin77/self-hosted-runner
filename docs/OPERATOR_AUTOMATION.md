# Operator Automation (On-host systemd timers)

This document shows how to enable on-host automation for GSM→Vault sync and ephemeral runner cleanup using systemd timers (recommended when GitHub Actions and PR releases are disallowed).

Files installed:
- `scripts/systemd/vault_sync.service` and `vault_sync.timer`
- `scripts/systemd/cleanup_ephemeral.service` and `cleanup_ephemeral.timer`
- `scripts/infra/install_systemd_services.sh` — installer to copy units and enable timers

Pre-requisites:
- Host with `gcloud` and `vault` CLIs installed and authenticated (service account or workload identity).
- `gcloud` configured with a service account that has `secretmanager.versions.access` and `compute.instances.list`/`compute.instances.delete` as needed.
- `vault` CLI available and `VAULT_ADDR` + authentication configured (or tokens securely provisioned).

Installation (operator):

```bash
sudo ./scripts/infra/install_systemd_services.sh
```

Configuration:
- Edit `/etc/systemd/system/vault_sync.service` drop-in or the unit file environment variables to set `GSM_SECRET_NAME`, `VAULT_PATH`, `GCP_PROJECT`, and `VAULT_ADDR`.
- Edit `/etc/systemd/system/cleanup_ephemeral.service` drop-in to set `PROJECT`, `ZONE`, and `TTL_HOURS`.

Notes:
- Units are oneshot and run via timers; you can start them manually with `systemctl start vault_sync.service`.
- All scripts are idempotent and safe to re-run.
- For fully hands-off operation, ensure the host's service account keys are rotated via KMS and that the host is monitored.

Security:
- Keep service account keys out of the repo. Use workload identity or VM service accounts where possible.
- Use KMS-backed secret storage and rotation for any tokens.

Monitoring & Alerts:
- Add monitoring to detect repeated failures of `vault_sync.service` or `cleanup_ephemeral.service` via systemd journal alerts.

