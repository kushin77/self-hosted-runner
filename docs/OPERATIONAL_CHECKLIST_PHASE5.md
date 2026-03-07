# Phase 5 Operational Checklist — Hands-Off Automation

**Last Updated**: 2026-03-07

This checklist captures the immediate operational steps to validate Phase 5 automations, run safe runtime tests, and onboard required secrets for Slack alerts and remote dispatching.

1. Authenticate `gh` CLI in this environment
   - Purpose: allow runtime workflow dispatch and issue creation from CI/agent shell
   - Commands to run locally:
     ```bash
     gh auth login
     # or use a PAT (preferred for automation):
     export GH_TOKEN="<PAT_WITH_repo_and_workflow_scopes>"
     gh auth status
     ```

2. Add internal secrets to repository (required for alerts & runtime ops)
   - `SLACK_WEBHOOK_URL` — Slack incoming webhook for alerts
   - `GSM_AUDIT_BUCKET` — optional GCS bucket name for archival
   - `GH_RUNNER_ADMIN_KEY` — admin SSH key (if needed for runner remediation)
   - How to add (recommended):
     ```bash
     gh secret set SLACK_WEBHOOK_URL --body "$SLACK_WEBHOOK_URL" --repo kushin77/self-hosted-runner
     gh secret set GH_TOKEN --body "$GH_TOKEN" --repo kushin77/self-hosted-runner
     ```

3. Run runtime tests (manual dispatch)
   - `test-gsm-retrieve.yml` — verifies GSM → GitHub Secrets sync
   - `test-vault-rotation.yml` — performs a dry-run AppRole rotation (no destructive actions)
   - Dispatch commands:
     ```bash
     gh workflow run test-gsm-retrieve.yml --repo kushin77/self-hosted-runner
     gh workflow run test-vault-rotation.yml --repo kushin77/self-hosted-runner
     ```

4. Monitor first scheduled runs
   - `sync-gsm-to-github-secrets.yml` runs every 6 hours
   - `credential-monitor.yml` runs every 5 minutes
   - Verify via GitHub Actions UI or `gh run list`

5. Verify idempotency and recovery scripts
   - Run locally on a staging environment where safe:
     ```bash
     bash scripts/automation/validate-idempotency.sh
     bash scripts/verify-recovery.sh
     ```

6. External blockers to escalate (if not already):
   - #1007: MinIO DNS for archival — NetOps
   - #1008: SSH key audit and consolidation — Security/Infra

7. Post-validation actions
   - If runtime tests pass: close issue tracking Phase 5 runtime validation
   - If failures observed: open a focused incident issue with logs and assign `ops` and `infra`

---

Owner: ops-team (@akushnir)
