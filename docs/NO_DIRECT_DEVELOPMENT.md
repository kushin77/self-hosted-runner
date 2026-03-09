# No Direct Development to Worker Nodes or Main Branch

Policy: All repository changes must be made via pull requests and CI-based validation. Direct edits on the production worker node or direct pushes to `main` are prohibited.

Why:
- Ensures immutable, auditable history and reviewability.
- Enforces ephemeral credential usage (GSM/Vault/KMS) for all runs.
- Maintains idempotent, no-ops automation and prevents drift.

Rules:
1. No direct edits on worker nodes (192.168.168.42 or others).
2. No direct pushes to `main`; use feature branches and PRs.
3. All PRs must include:
   - A passing CI status (lint, tests, `yamllint`, credential validation).
   - At least one approving review from code owners.
   - No plaintext secrets in diffs.
4. Required status checks should include:
   - `yamllint` / workflow YAML validation
   - `python-lint` / `ruff` or similar for scripts
   - `validate-credential-providers` (Phase 2 provider validation)
   - Integration tests / smoke tests where applicable
5. Branch protection/Repository settings (operator action):
   - Require pull request reviews before merging
   - Require status checks to pass before merge
   - Restrict who can push to `main` (admins only, for emergency revert)
   - Enforce signed commits if configured
6. Emergency procedure:
   - If an immediate fix on the worker node is unavoidable, open an issue with the `emergency` label, document the change in the issue, and follow up by creating a PR that pulls the change back into `main` for audit and rollback.

Operator actions (manual):
- Enable branch protection for `main` and enforce the above checks.
- Configure required status checks in GitHub settings to reference the CI workflows listed.
- Add `CODEOWNERS` entries for critical paths.

References:
- `docs/REPO_SECRETS_REQUIRED.md` — repository secrets required for Phase 2
- `CONTRIBUTING.md` — development guidelines (update if needed)

This file is informational only and does not contain secret values. To implement enforcement, please enable branch protection and required checks in repository settings or grant me permission to open a PR that adds GitHub Actions enforcement workflows.