Security remediation runbook — exposed private key

Summary
- A private key was committed to `runner-keys/self-hosted-runner.ed25519` and has now been redacted from the repository HEAD.

Immediate actions (0-30 minutes)
1. Revoke and rotate the compromised key immediately:
   - If this key was registered as a self-hosted runner, remove the runner from GitHub/GitLab and rotate the registration.
   - If the key was used for SSH access, rotate the corresponding authorized_keys entries and remove the old key.
2. Create a new keypair locally and store the private key in GSM or Vault (do NOT commit it).
   - Example (generate ed25519): `ssh-keygen -t ed25519 -f /tmp/runner-key && gcloud secrets versions add runner-key --data-file=/tmp/runner-key --project=$PROJECT`
3. Update systems that used the key to reference the new secret from GSM/Vault/KMS.

History rewrite (1-4 hours, security team)
- To fully remove the secret from git history, coordinate with security and follow these steps:
  1. Rotate the secret (do not delay while scheduling history rewrite).
  2. Use `git filter-repo` or the BFG to remove the file from history:
     - Example: `git filter-repo --path runner-keys/self-hosted-runner.ed25519 --invert-paths`
  3. Force-push the cleaned branch to the remote (coordinate with all contributors): `git push --force --all` and `git push --force --tags`.
  4. Invalidate any caches/backups that might contain the secret.

Verification
- Ensure the old key no longer grants access.
- Confirm the new key is stored in GSM/Vault and referenced by deployments.
- Run a repo scan (gitleaks) to confirm no remaining traces.

Notes
- Rewriting history is disruptive; do it only after rotating the secret and coordinating with maintainers and CI.
- This remediation replaces the file in the repo HEAD but does not by itself remove the secret from history; follow the History rewrite steps.

Contact: @kushin77 (ops), @BestGaaS220 (security)
