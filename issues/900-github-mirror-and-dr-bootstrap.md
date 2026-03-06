Title: GitLab → GitHub push mirror + automated DR bootstrap

Goal: Ensure one-way push mirror to a private GitHub repo is documented, tested, and provide an automated bootstrap script to restore GitLab from the GitHub backup.

Checklist:
- [x] Document mirror method (SSH deploy-key and/or PAT) and target private repo in `config/cicd/.gitlab-ci.yml`. (completed via workflow update)
- [x] Add `scripts/scm/gitlab-github-sync.sh` as a documented tool; add test that a dummy commit to GitLab updates GitHub within 10 minutes. (Integrated into `ci_templates/mirror-to-github.yml` logic)
 - [x] Implement `bootstrap/restore_from_github.sh` (idempotent) that can: install GitLab, restore secrets from encrypted backup, restore DB backup if present, and import projects from GitHub mirror. (implemented: `bootstrap/restore_from_github.sh`)
 - [x] Add CI job that validates mirror health after each successful merge to `main` (optional: push --mirror via runner for near-instant sync). (template added at `ci_templates/mirror-to-github.yml` and wired into `.gitlab-ci.yml`)
 - [ ] Test full DR bootstrap on a throwaway VM and record RTO/RPO metrics.
 - [x] Added automation helper: `scripts/ci/bootstrap_automation.sh` to rotate deploy keys, set protected variables, and optionally create a pipeline schedule via API (requires `GITLAB_API_TOKEN`/`GITHUB_TOKEN`) (implemented).

Notes:
- This complements issues/004-implement-restore-pipeline.md; use that issue as the parent for automation work.

Status: Closed

Closure note: Implementation artifacts (restore script, CI template, and automation) have been completed and a credential-less simulation was executed on 2026-03-06 (see `docs/DR_RUNBOOK.md` for simulated metrics). Live verification steps remain tracked in `issues/905-run-live-dr-dryrun.md`. Closing this issue as implementation complete and ready for operational validation.
