# Request: Phase 5 Runtime Validation — Action Required

Use this template to create a GitHub issue requesting operator action to authenticate `gh` in the execution environment and run Phase 5 runtime tests.

Title: "Action Required: Phase 5 Runtime Validation — Authenticate GH CLI & Run Tests"

Body:

```
Summary:
We have merged Phase 5 automation (credential rotation, revocation, GSM→GitHub sync, DR enhancements). To validate runtime behavior we need an operator to:

1. Authenticate the `gh` CLI in the execution environment (or provide `GH_TOKEN` as a repository secret).
2. Add `SLACK_WEBHOOK_URL` as a repository secret for alerting.
3. Dispatch the following workflows and observe results:
   - `test-gsm-retrieve.yml` (verifies GSM→GitHub Secrets sync)
   - `test-vault-rotation.yml` (dry-run AppRole rotation)

Commands to run (operator):

```bash
gh auth login
gh secret set SLACK_WEBHOOK_URL --body "$SLACK_WEBHOOK_URL" --repo kushin77/self-hosted-runner
gh secret set GH_TOKEN --body "$GH_TOKEN" --repo kushin77/self-hosted-runner
gh workflow run test-gsm-retrieve.yml --repo kushin77/self-hosted-runner
gh workflow run test-vault-rotation.yml --repo kushin77/self-hosted-runner
```

Acceptance criteria:
- Both test workflows complete with `success` or `skipped` (if dry-run constraints apply).
- `sync-gsm-to-github-secrets.yml` updates secrets as expected (check GitHub Secrets and workflow logs).
- No unexpected failures in `credential-monitor.yml` after rotation.

If successful, please close this issue and add a comment with run links and any follow-up recommendations.

Assignee: @ops-team
Labels: `phase5`, `runtime-validation`, `action-required`

```
