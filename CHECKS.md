# Repository Required Checks & Enforcement

This document describes the required repository checks and how to enable branch protection to enforce immutable, sovereign, ephemeral, independent, fully automated hands-off operations.

## Required Checks

- `continuous-secrets-scan` — daily and PR secret scans using `sanitize-repo-security.sh` and `gitleaks`.
- `precommit-ci` — runs `pre-commit run --all-files` on PRs and pushes.
- `verify-required-secrets` — verifies presence of required repository secrets and files an issue if missing.
- `monthly-secrets-history-scan` — full-history `gitleaks` scan (monthly) to detect past leaks.

## Branch Protection Recommended Settings (main)

1. Require pull request reviews before merging (1 reviewer minimum).
2. Require status checks to pass before merging — enable the three checks above.
3. Require branches to be up to date before merging (merge queue strategy optional).
4. Restrict who can push to `main` (admins + CI bots only).
5. Enforce signed commits if your team uses commit signing.

## Enforcing Pre-commit in CI

We provide `pre-commit` configuration and a `precommit-ci` workflow that runs on PRs. To enforce it:

1. Add `precommit-ci` to required checks in branch protection.
2. Optionally add a server-side enforcement tool or GitHub App.

## Secrets Configuration

Before enabling auto-deploy workflows, ensure the following repository secrets exist (Settings → Secrets → Actions):

- `VAULT_ADDR`
- `VAULT_BOOTSTRAP_TOKEN`
- `VAULT_ROLE_ID`
- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`
- `MINIO_ENDPOINT`

Use the `verify-required-secrets` workflow to validate presence. A local helper `scripts/security/verify_required_secrets.sh` is available.

## Operational Playbook

- If `verify-required-secrets` opens an issue, assign to `ops` and resolve by adding missing secrets.
- PRs that fail `precommit-ci` should be blocked until fixes are applied.
- Use the `continuous-secrets-scan` artifacts to triage potential findings.

## Rollout Plan

1. Create branch protection with required checks enabled for `main`.
2. Merge this `CHECKS.md` via PR to document the policy.
3. Run `verify-required-secrets` to confirm secrets are present.
4. Enable scheduled scans and monthly history scans.

---

If you want, I will open a PR with this file now and post the PR link to Issue #846 for audit and approval.