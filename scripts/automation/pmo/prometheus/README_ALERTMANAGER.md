Alertmanager config generation and deployment
=========================================

This directory contains a template and helper script to safely generate `alertmanager.yml` from environment secrets without committing secrets into the repository.

Files:
- `alertmanager.yml.tpl` — the template containing `${SLACK_WEBHOOK_URL}` and `${PAGERDUTY_SERVICE_KEY}` placeholders.
- `.env.template` — example placeholder values (do NOT commit real secrets).
- `generate-alertmanager-config.sh` — script that generates `alertmanager.yml` from the template using variables in `.env`.

Recommended workflow (on the host where the compose stack runs):

1. Copy the template to `.env` and populate secrets (or provision them via your secret manager):

```bash
cp .env.template .env
# Edit .env and set SLACK_WEBHOOK_URL and PAGERDUTY_SERVICE_KEY securely
```

2. Generate the `alertmanager.yml` file:

```bash
cd scripts/automation/pmo/prometheus
./generate-alertmanager-config.sh
```

3. Verify `alertmanager.yml` is present and correct, then run docker compose up on the host (or restart the `alertmanager` service):

```bash
docker compose -f docker-compose-observability.yml up -d alertmanager
```

Notes:
- The generator prefers `envsubst` (from gettext) and falls back to `perl` if present.
- Do not commit `.env` or the generated `alertmanager.yml` into the repo. Use a secrets manager or CI variables for production.
