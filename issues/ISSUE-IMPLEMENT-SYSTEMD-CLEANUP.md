Title: Implement systemd-based Idle Cleanup and On-Demand Activation

Status: closed

Description:
- Provide a local, systemd-based automation mechanism that runs `idle-resource-cleanup.sh` every 5 minutes and allows manual on-demand activation via `on-demand-activation.sh`.

Actions taken:
- Added `systemd/idle-cleanup.service` and `systemd/idle-cleanup.timer`.
- Added `systemd/on-demand-activation.service` for manual activation.
- Updated `scripts/cost-management/setup.sh` to attempt installation of systemd units (idempotent) and enable the timer.

Verification:
- Systemd unit files present in repository.
- Setup script attempts to install and enable timer if `systemctl` is available and `sudo` is permitted.

Notes:
- Manual copy or admin intervention may be necessary on systems without `sudo` access from the current user.
- This issue was closed after unit files and setup changes were added to repository.
Additional notes (2026-03-12):
- Changed cleanup script to be opt-in safe-by-default. The script now requires `ENABLE_IDLE_CLEANUP=true` or `FORCE_CLEANUP=true` to perform destructive actions. The repository `systemd/idle-cleanup.service` sets `ENABLE_IDLE_CLEANUP=false` to avoid accidental production shutdowns. Operators who intend to enable automated cleanup must explicitly set `ENABLE_IDLE_CLEANUP=true` in a unit drop-in or environment.
- Recommendation: Do NOT enable the timer on production hosts. Use manual on-demand activation for maintenance windows instead.
