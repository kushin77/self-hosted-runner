# Alerting & Monitoring (stub)

This file records recommended monitoring and alerting for the governance enforcement systems.

Recommended alerts:
- Cloud Run `prevent-releases` failures: alert on high error rate or crashloop.
- Cloud Scheduler job failures: alert when `prevent-releases-poll` last run status is FAILED or job state != ENABLED.
- Secret access failures: monitor Cloud Run logs for `Permission denied` on secrets or failed secret fetch attempts.
- GitHub API rate/401 errors: create alert on repeated 4xx/5xx responses from enforcement service.

Rotation reminders:
- Follow `docs/ROTATE_GITHUB_TOKEN.md` for scheduled rotation of `github-token` in GSM.

Owner: Platform Security
