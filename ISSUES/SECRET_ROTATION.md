Title: SECRET ROTATION & REMOVAL — canonical secret artifacts

Summary:
The repository previously contained archived secret artifacts and example plaintext secrets. This issue tracks the removal of artifacts from the repo, rotation of affected credentials, and verification of secret purge from Git history.

Actions taken:
- Redacted example DB password in `nexus-engine/docker-compose.yml` and `nexus-engine/README.md`.
- Added `docs/SECRETS_INVENTORY.md` and updated `.gitignore` to include secret artifacts/binaries.

Remaining actions:
- [ ] Rotate any credentials that may have been exposed historically (GSM/Vault rotation).
- [ ] Perform a full secret scan (truffleHog/git-secrets) across branches and PRs.
- [ ] If historical exposure confirmed, purge from git history using `git-filter-repo`/BFG and force-push cleaned refs.
- [ ] Validate all CI pipelines use GSM/Vault and do not log secrets.

Verification steps:
1. Run `trufflehog git file://$(pwd)` or equivalent secret scanner.
2. Confirm no secrets found in default branch and active release branches.
3. Document rotation events and update `docs/SECRETS_INVENTORY.md` with new secret names.

Owner: @akushnir
