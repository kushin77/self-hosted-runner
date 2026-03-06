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
- [x] Integrated `maintenance:gitlab_backup` and GitHub mirroring into `config/cicd/.gitlab-ci.yml`.
- [x] Added `scripts/ci/bootstrap_automation.sh` for automated secret/key rotation.

Next actions:
- Perform the first live DR dry-run on a throwaway VM to gather final RTO/RPO metrics (see `issues/905-run-live-dr-dryrun.md`).
- Record results in `docs/DR_RUNBOOK.md` and close verification tasks in `issues/905-run-live-dr-dryrun.md`.

Status: Closed

Closure note: Core restore pipeline and orchestration scripts have been implemented and validated via a credential-less simulation on 2026-03-06 (see `docs/DR_RUNBOOK.md`). Live DR dry-run and final RTO/RPO measurement are tracked in `issues/905-run-live-dr-dryrun.md`. Closing this issue as implementation complete.
