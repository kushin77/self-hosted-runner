# Issue 1615 — Automation record

Status: pending remote API action (auto-merge enablement)

Actions performed locally (enforced in repo):

- Verified `.github/workflows/` is empty; no active workflows present.
- `.githooks/prevent-workflows` exists and will block commits modifying `.github/workflows/`.
- Added automation scripts:
  - `scripts/github/enable-auto-merge.sh` — enables `allow_auto_merge` via `gh` or REST API.
  - `scripts/github/post-issue-comment.sh` — posts a comment to issue #1615 and closes it via API.
- Created `scripts/github/enable-auto-merge.sh` and `scripts/github/post-issue-comment.sh` and made them executable.
- Verified repository contains `NO_GITHUB_ACTIONS.md` and enforcement scripts `scripts/validate-automation-framework.sh`.

Required remote/admin actions (need a `GITHUB_TOKEN` with `repo` admin privileges or `gh` auth):

1. Run the enable script locally or provide a token so automation can run it here:

```bash
GITHUB_TOKEN=<token_with_repo_admin> ./scripts/github/enable-auto-merge.sh
GITHUB_TOKEN=<token_with_repo_admin> ./scripts/github/post-issue-comment.sh
```

2. (Optional) In repo Settings → Actions → General, set `Allow Actions` to `Disabled` or `Allow local only` as desired. Automation also supports the API call:

```bash
curl -X PUT -H "Authorization: Bearer <token>" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/kushin77/self-hosted-runner/actions/permissions \
  -d '{"enabled":false,"allowed_actions":"none"}'
```

3. Verify branch protection & release policies to prevent PR-based releases (use `gh` or API to adjust `releases` and protect `main`).

Governance posture applied (local): immutable, ephemeral, idempotent, no-ops, hands-off. Credential strategy: GSM / Vault / KMS recommended and referenced in docs.

Notes:
- I cannot call the GitHub API from this environment without a `GITHUB_TOKEN` or an authenticated `gh` session. Provide a token if you want me to run the remote steps now.
- If you prefer, run the two commands in step (1) locally — the scripts are idempotent and safe to run repeatedly.

Signed-off-by: automation
