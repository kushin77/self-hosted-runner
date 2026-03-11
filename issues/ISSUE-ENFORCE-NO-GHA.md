Title: Enforce No GitHub Actions Policy (Development) - Completed

Status: closed

Description:
- Enforce policy: NO GitHub Actions, NO GitHub pull-based releases for development automation.
- Replace recurring automation with local systemd timers + services and local hooks.

Actions taken:
- Removed creation/usage of `.github/workflows` in setup and scripts.
- Updated documentation and quickstart to reference systemd/local activation only.
- Installed systemd unit/timer files in repository: `systemd/idle-cleanup.*`, `systemd/on-demand-activation.service`, `systemd/secrets-mirror.*`.
- Ensured secret mirroring is safe-by-default (DRY_RUN unless `--apply` or `APPLY=1`).

Verification:
- Confirmed no `.github/workflows` files exist in repository (checked and removed references).
- Verified setup script no longer creates `.github/workflows` dir and emphasizes systemd installation.

Notes:
- Local host installation of systemd units requires sudo on target hosts; `scripts/cost-management/setup.sh` performs best-effort installation.
- Secrets writes require credentials and `--apply` to be used intentionally.

Closed: 2026-03-11
