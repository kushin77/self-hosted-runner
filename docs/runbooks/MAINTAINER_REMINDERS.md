# Maintainer Reminders

This repository includes two automated reminder mechanisms:

- `weekly-maintainer-reminder.yml` — posts weekly comments directly on maintainer issues (already active).
- `weekly-maintainer-webhook.yml` — posts a webhook POST to an external URL for cross-platform reminders (Slack, calendar, PagerDuty, etc.).

To enable webhook reminders:

1. Add a repository secret named `MAINTAINER_REMINDER_WEBHOOK` containing the target URL.
   - For Slack, use an incoming webhook URL.
   - For calendar automation or other systems, use the service's incoming webhook URL or an intermediary endpoint.
2. The workflow runs every Monday at 09:00 UTC and on manual dispatch.
3. The payload is a simple JSON object with `issue` and `text` fields. Customize the workflow if you need richer payloads.

Issues targeted by reminders: `#1156`, `#1157`.
