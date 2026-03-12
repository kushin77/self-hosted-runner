# Incident Response & Escalation Runbook (Phase 6)

Purpose: provide automated, idempotent workflows for incident creation, escalation, mitigation, and postmortem capture.

1. Incident detection sources
  - Prometheus alertmanager
  - SLO burn-rate alerts
  - Synthetic monitoring failures

2. Automated actions (idempotent)
  - Create incident ticket in tracking system via API (script: `scripts/phase6/incident_create_ticket.sh`)
  - Post incident summary to on-call channel (Slack/PagerDuty integration)
  - Trigger runbook steps and attach logs

3. Escalation policy
  - Page primary on call for CRITICAL alerts
  - If no acknowledgement in 10 minutes, escalate to secondary
  - After 30 minutes, escalate to engineering manager

4. Post-incident
  - Capture timeline & root cause in incident ticket
  - Run automated forensic scripts to collect state (logs, pod dumps)
  - Create postmortem template and assign owner

5. Files & automation
  - `scripts/phase6/incident_create_ticket.sh` — create/update ticket via API
  - `monitoring/RUNBOOK.md` — links to incident sections
