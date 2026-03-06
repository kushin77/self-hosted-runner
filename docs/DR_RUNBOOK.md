Disaster Recovery Runbook (DR Drill)

Purpose
- Step-by-step runbook to validate restoration of GitLab, runners, and Vault from the GitHub backup and encrypted backups.

Prerequisites
- Access to GitLab backup S3 bucket and decryption keys (sops/age). Keep keys offline and available to drill operators.
- A throwaway VM or cloud instance matching the documented VM spec.
- Network/DNS controls to point `GITLAB_DOMAIN` at the test VM (or use /etc/hosts entry).

Quick drill steps
1. Provision a throwaway VM (Ubuntu 22.04 recommended) with internet egress and at least 4 vCPU, 16GB RAM, 120GB disk.
2. Copy repository code to VM or ensure `bootstrap/restore_from_github.sh` is accessible.
3. Export env vars on VM:
   - `GITHUB_BACKUP_URL` (required)
   - `GITLAB_DOMAIN` (required)
   - `RESTORE_S3_BUCKET` (if using S3 backups)
   - `DECRYPT_CMD` or `AGE_KEY_FILE` / `SOPS` config
   - `GITLAB_ROOT_PASSWORD` (optional)
4. Run: `./bootstrap/restore_from_github.sh` and watch output.
5. Run `./scripts/dr/drill_run.sh` to perform post-restore health checks.
6. Validate:
   - GitLab web UI reachable at `https://${GITLAB_DOMAIN}`
   - `YAMLtest-sovereign-runner` job runs on re-registered runner
   - A sample Vault-authenticated job can fetch a secret (requires Vault access)

Post-drill tasks
- Record RTO (time from VM provision start to GitLab healthy) and RPO (latest commit recovered).
- Revoke any temporary keys used for the drill and store them securely.
- Update `issues/903-quarterly-dr-drill.md` with results and close the drill action item when verified.
