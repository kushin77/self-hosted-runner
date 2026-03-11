# Repository Policy: No GitHub Actions / No PR Releases

Purpose
-------
This repository enforces a direct-development, direct-deploy model: no GitHub Actions workflows and no GitHub pull-request release flows.

Policy
------
- Do not add or enable files under `.github/workflows/`.
- All automation must be executed from hardened self-hosted runners or cron jobs.
- CI/CD automation must be implemented as shell scripts in `scripts/` and run on approved runners.
- Credentials must flow via GSM → Vault → KMS patterns; never hard-coded in repository.

Enforcement
-----------
1. Remove or archive existing workflow files. Use `scripts/policy/remove_workflows.sh` to locate and archive any `.github/workflows` content.
2. Review pull requests or branches that attempt to reintroduce workflows.
3. Repo owners must not enable GitHub Actions in repository settings.

Enforcement Status (automated)
-------------------------------
- As of 2026-03-11T17:53:10Z UTC the repository has no active `.github/workflows/` files. The enforcement helper `scripts/enforce/no_github_actions_check.sh` reports compliance.
- An archival sweep was run and archived workflow artifacts were moved to `archived_workflows/2026-03-11_175310Z/` (commit pending). Use `git add -A && git commit -m 'chore(policy): archive GitHub workflows'` to finalize the archive.
- A pre-commit hook `.githooks/prevent-workflows` and the enforcement script prevent accidental re-addition.
- Automation note: the repository now uses scheduled systemd timers and hardened self-hosted runners for automation; see `DEPLOYMENT/AUTOREVERIFY_README.md` for the new re-verification automation.

Exceptions
----------
Any exception requires explicit sign-off from the repository owner and governance committee.

Contact
-------
Open a ticket in the repository issues for policy exceptions or clarifications.
