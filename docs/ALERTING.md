# Alerting & Receivers

This document describes the baseline Alertmanager configuration and deployment steps.

Files:
- `monitoring/alertmanager/alertmanager.yml` — baseline Alertmanager routes & receivers (placeholders)
- `ansible/playbooks/deploy-alertmanager-config.yml` — Ansible playbook to deploy config to monitoring hosts

Secrets / Configuration
- `slack_webhook` should be stored securely (Ansible Vault or GitHub Actions secrets) and supplied when deploying the playbook.
- SMTP settings in `alertmanager.yml` are placeholders and should be replaced with your organization's mail relay.

Deployment

```bash
ansible-playbook -i inventory/hosts ansible/playbooks/deploy-alertmanager-config.yml
```

Follow-up
- Tune alert rules (`monitoring/prometheus/eiq-alerts.yml`) for realistic thresholds.
- Add Alertmanager receivers for PagerDuty or Slack with proper webhook/credentials.
- Configure Prometheus to read the alerting rules (already present under `monitoring/prometheus/`).
