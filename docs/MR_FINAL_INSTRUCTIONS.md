# Final MR Instructions — GitLab Migration

This file contains the final, reviewer-facing steps to merge and activate the GitLab migration MR safely.

Pre-merge checklist (ops):
- Confirm CI variables exist: set `GITLAB_TOKEN` (api scope) as masked & protected in Project → Settings → CI/CD → Variables.
- Confirm `CI_PROJECT_ID` is available in CI (GitLab provides it automatically).
- Confirm runner is registered and has tag `automation` (or allow untagged runners if desired).
- Run the MR validation pipeline (it runs `validate-automation-gitlab.sh` with `SKIP_ISSUE_TEST=true`). Ensure it passes.

Merge steps:
1. Merge MR: `automation/gitlab-migration` into `main` after review.
2. In GitLab, go to CI/CD → Pipelines and manually trigger the `bootstrap:provision` job (it is manual and gated).
   - This job will run `create-ci-variables-gitlab.sh` and `create-required-labels-gitlab.sh` using `GITLAB_TOKEN`.
3. Confirm labels present: open Project → Issues → Labels and verify `state:backlog`, `type:security`, `priority:p0`, etc.

Post-merge activation:
- Create pipeline schedules (SLA monitor) via UI or run the helper:
  ```bash
  PROJECT_ID=<id> GITLAB_TOKEN=<token> scripts/gitlab-automation/create-schedule-gitlab.sh "SLA Monitor" "0 */4 * * *" main
  ```
- Optionally, run triage and SLA monitor once manually:
  ```bash
  PROJECT_ID=<id> GITLAB_TOKEN=<token> bash scripts/gitlab-automation/triage-issues-gitlab.sh
  PROJECT_ID=<id> GITLAB_TOKEN=<token> bash scripts/gitlab-automation/sla-monitor-gitlab.sh
  ```

Rollback plan:
- If provisioning causes issues, disable the `bootstrap` job and delete created labels via API, or restore from label backup.
- Runner rollback: re-register previous GitHub Actions runner if needed using your `actions-runner-backup-*.tgz`.

Contact & verification
- Ping `@akushnir` after provisioning to verify triage and sample issues.
- Verify first SLA run and review `sla:breached` labels for false positives.

This completes the recommended operational steps. Merge when ready.
