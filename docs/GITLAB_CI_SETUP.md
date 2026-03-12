# GitLab CI Setup & Best Practices

This document lists recommended CI/CD variables, runner configuration, and scheduled pipelines to run the migrated automation safely.

CI variables (Project → Settings → CI/CD → Variables)
- `GITLAB_TOKEN` : personal access token or project access token with `api` scope (masked, protected)
- `CI_PROJECT_ID` : GitLab project numeric ID (can be injected by CI as `CI_PROJECT_ID`)
- `ASSIGNEE_USERNAME` : default assignee username used by triage scripts (e.g., `akushnir`)
- `GITLAB_API_URL` : optional if using GitLab self-hosted (default `https://gitlab.com/api/v4`)

Runner configuration
- Prefer registering a dedicated runner for automation jobs.
- Executor recommendation:
  - `shell` executor for lightweight scripts on your existing host
  - `docker` executor when you need isolation (use a small Python image)
- Recommended runner tags: `automation`, `ci`, `self-hosted`
- Limit runner access by using `protected` jobs for production-sensitive tasks.

Pipeline schedules (UI: Project → CI/CD → Schedules)
- SLA monitor: run every 4 hours
  - Cron: `0 */4 * * *`
  - Target branch: `main` (or your default)
  - Variables: `SKIP_ISSUE_TEST=false` (or keep reporting-only by setting true)

- Nightly triage: run daily at 03:00 UTC
  - Cron: `0 3 * * *`
  - Job: `triage:manual` (manual/triggered by schedule)

Creating schedules via API (example)
```bash
# Create SLA schedule (requires GITLAB_TOKEN and CI_PROJECT_ID)
curl -sS --request POST "${GITLAB_API_URL:-https://gitlab.com/api/v4}/projects/${CI_PROJECT_ID}/pipeline_schedules" \
  -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"description": "SLA Monitor (every 4h)", "ref": "main", "cron": "0 */4 * * *", "cron_timezone": "UTC"}'
```

Security & best-practices
- Protect `GITLAB_TOKEN` and restrict scope to `api`.
- Set `masked` for all secrets and use `protected` variables for protected branches.
- Limit who can edit pipeline schedules and CI variables (Project Settings → Members / Maintainers only).

Testing & rollout
- Create a feature branch and open a Merge Request for the `automation/gitlab-migration` branch changes.
- Use `SKIP_ISSUE_TEST=true` for validation runs in CI before enabling live test issue creation.
- Once validated, enable schedules and set `SKIP_ISSUE_TEST=false` to allow live runs (ensure `GITLAB_TOKEN` has `api` scope).

If you want, I can add the API calls to create schedules and a small helper script to manage CI variables automatically. Want me to add those scripts and push them to the migration MR?
