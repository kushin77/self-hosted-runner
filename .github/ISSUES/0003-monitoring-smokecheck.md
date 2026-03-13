Title: Monitoring: Add recurring smoke-check and alerting for portal
Status: open

Summary:
- Ensure the `portal/docker/smoke-check.sh` is run periodically (systemd timer or cronjob) and failures are alerted to the ops channel.
- Add container-level readiness probes and integrate with existing observability (Cloud Monitoring / Prometheus).

Acceptance Criteria:
- Provide a systemd timer example or cron entry in `portal/docker/`.
- Configure alerts (pager/sms/email) for repeated smoke-check failures.
