Title: Encrypted backup of GitLab config and secrets

Goal: Ensure `gitlab.rb`, `gitlab-secrets.json`, and DB backups are encrypted, stored off-host, and covered by automated backup+restore tests.

Checklist:
 - [x] Create `scripts/backup/gitlab_backup_encrypt.sh` that runs `gitlab-backup create`, copies `/etc/gitlab/gitlab-secrets.json` and `/etc/gitlab/gitlab.rb`, encrypts with `sops`/`age`, and uploads to configured S3 bucket. (implemented: `scripts/backup/gitlab_backup_encrypt.sh`)
 - [x] Add a scheduled pipeline job to run backups (job added: `maintenance:gitlab_backup` in `config/cicd/.gitlab-ci.yml`). Please add a GitLab pipeline schedule (UI) for daily cadence and set protected variables.
 - [ ] Document restore steps and ensure `bootstrap/restore_from_github.sh` pulls these encrypted files for reconfigure.
 - [ ] Add test that validates backup files decrypt correctly and contain expected keys (sanitized test only).
 - [x] Create `scripts/backup/gitlab_backup_encrypt.sh` that runs `gitlab-backup create`, copies `/etc/gitlab/gitlab-secrets.json` and `/etc/gitlab/gitlab.rb`, encrypts with `sops`/`age`, and uploads to configured S3 bucket. (implemented: `scripts/backup/gitlab_backup_encrypt.sh`)
 - [x] Add a scheduled pipeline job to run backups (job added: `maintenance:gitlab_backup` in `config/cicd/.gitlab-ci.yml`). Please add a GitLab pipeline schedule (UI) for daily cadence and set protected variables.
 - [x] Add `scripts/backup/prune_backups.sh` to prune older backup artifacts from S3 (implemented: `scripts/backup/prune_backups.sh`).
 - [ ] Document restore steps and ensure `bootstrap/restore_from_github.sh` pulls these encrypted files for reconfigure.
 - [ ] Add test that validates backup files decrypt correctly and contain expected keys (sanitized test only).

Security:
- Backup targets must be access-controlled and audit-logged. Store decryption keys offline in at least two secure locations.
