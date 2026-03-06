Title: GitLab → GitHub push mirror + automated DR bootstrap

Goal: Ensure one-way push mirror to a private GitHub repo is documented, tested, and provide an automated bootstrap script to restore GitLab from the GitHub backup.

Checklist:
- [ ] Document mirror method (SSH deploy-key and/or PAT) and target private repo in `config/cicd/.gitlab-ci.yml`.
- [ ] Add `scripts/scm/gitlab-github-sync.sh` as a documented tool; add test that a dummy commit to GitLab updates GitHub within 10 minutes.
- [ ] Implement `bootstrap/restore_from_github.sh` (idempotent) that can: install GitLab, restore secrets from encrypted backup, restore DB backup if present, and import projects from GitHub mirror.
 - [x] Implement `bootstrap/restore_from_github.sh` (idempotent) that can: install GitLab, restore secrets from encrypted backup, restore DB backup if present, and import projects from GitHub mirror. (implemented: `bootstrap/restore_from_github.sh`)
- [ ] Add CI job that validates mirror health after each successful merge to `main` (optional: push --mirror via runner for near-instant sync).
 - [ ] Add CI job that validates mirror health after each successful merge to `main` (optional: push --mirror via runner for near-instant sync). (template added at `ci_templates/mirror-to-github.yml` — wiring into `.gitlab-ci.yml` required)
- [ ] Test full DR bootstrap on a throwaway VM and record RTO/RPO metrics.
 - [ ] Test full DR bootstrap on a throwaway VM and record RTO/RPO metrics.

Notes:
- This complements issues/004-implement-restore-pipeline.md; use that issue as the parent for automation work.
