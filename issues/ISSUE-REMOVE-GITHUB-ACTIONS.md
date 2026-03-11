Title: Remove GitHub Actions Workflows and Replace with Local Automation

Status: closed

Description:
- Remove any GitHub Actions workflows that run cost-management automation.
- Replace with local systemd timer + services to enforce 5-minute idle cleanup and on-demand activation.
- Ensure no GitHub Actions or PR-based releases are used per policy.

Actions taken:
- Created `systemd/idle-cleanup.timer` and `systemd/idle-cleanup.service`.
- Created `systemd/on-demand-activation.service`.
- Updated `scripts/cost-management/setup.sh` to install and enable systemd timer (best-effort using sudo).
- Updated docs and checklists to remove GitHub Actions references.

Notes:
- This issue was closed after local automation was implemented in the repository.
