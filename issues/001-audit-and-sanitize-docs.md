Title: Audit & Sanitize repository docs and artifacts for token-like placeholders

Context:
- We previously redacted several example tokens; a broader audit is needed to locate remaining token-like literals across docs, workflows, and artifacts.

Goal:
- Produce a prioritized list of files requiring redaction and submit small PRs to replace literals with safe placeholders.

Actions:
1. Run a repository-wide search for common token patterns such as `ghp_`, the phrase "GITHUB_TOKEN" (no literal assignment), variables beginning with `VAULT_`, and AWS secret variable names (written here as `AWS[underscore]SECRET[underscore]ACCESS[underscore]KEY` to avoid inserting the literal token string into the repo).
2. Verify matches are not false positives (e.g., scripts that expect placeholders).
3. Prepare small, focused PRs that only change docs/workflow files to placeholders.
4. Track progress by closing or updating this file with the list of PRs and file paths.

Notes:
- Avoid committing real secrets. If a real secret is discovered, rotate and remove it immediately following org procedures.

Findings (scan run 2026-03-06):

- Many docs already use placeholders (examples: `docs/VAULT_CI_SETUP.md`, `docs/VAULT_DEPLOY_WORKFLOW_SETUP.md`).
- Tracked artifacts containing environment/test values remain and should be removed or redacted:
	- `artifacts/test-logs/vault-integration-2026-03-05.log` (contains `VAULT_ROLE_ID=test-role-id`).
	- Files under `actions-runner/_work/` included runner workspace copies with concrete VAULT_ROLE_ID values (removed from index where detected).
- Workflow templates and scripts correctly reference `VAULT_ROLE_ID`/`VAULT_SECRET_ID` as secrets (keep placeholders), but outputs or logs that capture those values must not be committed.

Immediate remediation performed:

- Removed known tracked artifact logs and added `.gitignore` entries for `artifacts/test-logs/` and `actions-runner/_work/` (cleanup PRs merged).
- Opened/merged small hygiene PRs to normalize placeholders; one normalization PR remains open (`fix/normalize-vault-placeholders`).

Next actions (recommended):

1. Create focused redaction PRs for any remaining tracked artifacts found by the scan (remove from index and add to `.gitignore`).
2. Merge pending placeholder normalization PRs and re-run `./scripts/automation/pmo/tests/test_runner_suite.sh`.
3. Coordinate with ops to provision temporary `VAULT_ADDR`/`VAULT_ROLE_ID`/`VAULT_SECRET_ID` on the self-hosted runner (or configure `vault-agent`) to run end-to-end CI tests; document steps in `issues/000-run-self-hosted-ci-with-vault.md`.
4. If historical commits contain secrets, plan and execute secret rotation.

I will prepare the small redaction PR(s) for remaining tracked files and push them to `chore/audit-and-sanitize-docs` for review.

