**Auto Merge & CI Rerun — Runbook**

- **Purpose**: Periodically rerun failed workflows and enable auto-merge on eligible PRs to support fully hands-off CI/CD operations.
- **Location**: `scripts/automation/auto_merge_worker.sh`
- **Schedule**: GitHub Actions workflow `.github/workflows/auto-merge-cron.yml` runs every 30 minutes and is manually dispatchable.
- **Idempotency**: The worker is safe to run repeatedly. It requests reruns (API is idempotent) and sets repository/PR settings where appropriate.
- **Permissions**: The workflow uses `GITHUB_TOKEN`; ensure the token has repo permissions (default in Actions). Admin enablement of `allow_auto_merge` may require a repository admin — the script will open an admin issue if it cannot enable the setting.
- **Logs**: Workflow uploads `auto-merge-log` artifact; local runs write logs to a temp directory and print log path.
- **To run manually**:

```bash
# locally (with GH CLI authenticated):
REPO_FULL=kushin77/self-hosted-runner ./scripts/automation/auto_merge_worker.sh

# in GitHub Actions: use workflow dispatch in GitHub UI or run the cron
```

- **Follow-ups**:
  - Rotate/verify secrets used by workflows (MINIO_*, registry credentials).
  - Optionally extend worker to post summaries to a tracking Issue when large numbers of reruns are queued.
