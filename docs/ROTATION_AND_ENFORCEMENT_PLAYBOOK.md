## Rotation & Enforcement Playbook

Purpose: concise, repeatable steps to rotate the GitHub PAT stored in GSM and keep enforcement immutable, ephemeral, idempotent, and hands-off.

1. Provision new token (ephemeral): generate a new PAT with minimal scopes (repo, admin:repo_hook if needed).

2. Add token to GSM (idempotent):

```bash
GCP_PROJECT=nexusshield-prod \
GITHUB_TOKEN_VALUE="<NEW_GITHUB_PAT>" \
./scripts/secrets/provision-github-token-to-gsm.sh github-token
```

3. Grant orchestrator SA access (least privilege):

```bash
gcloud secrets add-iam-policy-binding github-token --project=nexusshield-prod \
  --member="serviceAccount:nxs-automation-sa@nexusshield-prod.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

4. Dry-run the orchestrator (verify only):

```bash
GSM_PROJECT=nexusshield-prod GSM_SECRET_NAME=github-token \
  ./scripts/secrets/run-with-secret.sh -- ./scripts/github/orchestrate-governance-enforcement.sh --dry-run
```

5. Live-run the orchestrator (apply):

```bash
GSM_PROJECT=nexusshield-prod GSM_SECRET_NAME=github-token \
  ./scripts/secrets/run-with-secret.sh -- ./scripts/github/orchestrate-governance-enforcement.sh
```

6. Revoke old token in GitHub and rotate regularly (30/90 days as policy).

7. CI / Monitoring: add quick checks that fail if any workflow files reappear or if `allow_auto_merge` flips:

 - `gh api /repos/:owner/:repo --jq '.allow_auto_merge'` should be `true`
 - `gh api /repos/:owner/:repo/actions/permissions --jq '.enabled'` should be `false`

8. Recovery: if orchestration fails, use the audit issues created (see issues with "orchestrator run" tag) and re-run orchestrator after remediation.

Keep this playbook small and copyable into operator runbooks.
