Title: Implement deterministic, automated restore pipeline

Description
- Create a one-command restore pipeline that can rehydrate infrastructure and services from an immutable state snapshot in an isolated sandbox.

Acceptance
- Pipeline can be triggered from CI and runs in a sandbox project/account without affecting production.
- Includes verification tests and audit trail.

Owner: infra-team
Priority: high

Status: in-progress

Progress:
- [x] Added `bootstrap/restore_from_github.sh` — idempotent restore/bootstrap helper to import from GitHub backup and restore encrypted secrets (see `bootstrap/restore_from_github.sh`).
- [x] Added `scripts/backup/gitlab_backup_encrypt.sh` to create and encrypt GitLab backups for upload to object store.
- [x] Added `scripts/dr/drill_run.sh` — lightweight DR drill harness to run the bootstrap on a throwaway instance and verify basic health checks.

Next actions:
- Wire the restore into a protected CI pipeline and schedule a quarterly automated drill (issues/903-quarterly-dr-drill.md).
- Add automated verification tests and gather RTO/RPO metrics during a dry-run.
