# Governance Enforcement Summary

This file documents repository-level enforcement applied to achieve the
approved governance posture: immutable, ephemeral, idempotent, no-ops, and
hands-off automation. It also lists scripts and hooks installed locally to
prevent GitHub Actions workflows and PR-based release workflows.

Key policies
- Immutable: audit logs are append-only and automation records are committed.
- Ephemeral: deployment artifacts are ephemeral and auto-cleaned by orchestrator.
- Idempotent: all automation scripts are safe to re-run.
- No-Ops / Hands-off: automation (cron, external orchestrator) performs routine tasks.
- Credentials: GSM + Vault + KMS recommended for secret storage; reference docs in `CREDENTIAL_MANAGEMENT_GSM.md`.

Repository controls implemented (local)
- `.githooks/prevent-workflows` prevents commits that add/modify `.github/workflows/` files.
- `.githooks/prevent-tags` prevents pushing tags (and thus ad-hoc release pushes) unless `GIT_ALLOW_TAG_PUSH` is set.
- `scripts/install-githooks.sh` installs the `.githooks` into `.git/hooks` for local developer enforcement.
- Workflow files are archived under `.github/workflows.disabled` and `.github/workflows` is kept empty.

Remote actions (require admin token)
- `scripts/github/enable-auto-merge.sh` — enable repository auto-merge via API (requires `GITHUB_TOKEN`).
- `scripts/github/post-issue-comment.sh` — post a comment and close issue #1615 via API (requires `GITHUB_TOKEN`).
- `scripts/github/disable-actions.sh` — disable GitHub Actions via API (requires `GITHUB_TOKEN`).
- `scripts/github/disable-releases.sh` — best-effort script to reduce release automation and document policy.

Operational notes
- These local hooks and scripts are idempotent and reversible. Remote repo-level enforcement (Actions toggle, branch protection) requires an admin token and is recommended for final enforcement.
- After running remote API scripts, verify the following in the repository UI:
  - `Allow auto-merge` is enabled.
  - Actions permissions show `Allowed actions: none`.
  - Branch protections on `main` are in place to prevent PR-based release automation.
