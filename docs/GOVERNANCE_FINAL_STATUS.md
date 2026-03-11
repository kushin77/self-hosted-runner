# Governance Enforcement — Final Status (2026-03-11)

Status: Active and automated

Summary:
- Auto-merge enabled for `kushin77/self-hosted-runner`.
- GitHub Actions disabled at repository level.
- Branch protection applied to `main` (enforce_admins=true, no force pushes/deletions).
- Local git hooks installed to prevent `.github/workflows/*` changes.
- `prevent-releases` enforcement service deployed to Cloud Run and scheduled via Cloud Scheduler (`prevent-releases-poll`, every minute).
- Rotation reminder scheduled (`rotate-github-token-reminder`, weekly Mondays 09:00 UTC).
- `github-token` canonicalized in GSM; Cloud Run service account granted `roles/secretmanager.secretAccessor`.

Files and scripts added:
- `scripts/github/orchestrate-governance-enforcement.sh`
- `scripts/secrets/*` (helpers, rotation script)
- `apps/prevent-releases` (Cloud Run app)
- `scripts/monitoring/create-alerts.sh` (monitoring helper)
- `docs/ROTATE_GITHUB_TOKEN.md`, `docs/ALERTING_AND_MONITORING.md`, `docs/INCIDENT_RUNBOOK.md`

Ownership:
- Platform Security (primary)
- Automation Team (operators)

Next recommended actions:
- Implement Cloud Monitoring alerting policies (see `scripts/monitoring/create-alerts.sh`).
- Schedule regular rotation of `github-token` and automate validation.
- Add on-call contact and integrate alerts into PagerDuty/Slack.
