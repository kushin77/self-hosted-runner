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

Exceptions
----------
Any exception requires explicit sign-off from the repository owner and governance committee.

Contact
-------
Open a ticket in the repository issues for policy exceptions or clarifications.
