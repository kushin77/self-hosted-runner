# Phase 6 — Finalization & Runbook (2026-03-10)

## Summary
This file records the finalization steps and operator runbook after the Phase 6 deployment and postgres_exporter rollout.

Status: PRODUCTION LIVE — postgres_exporter deployed, Prometheus scraping, Postgres logs clean.

## Key Artifacts
- `scripts/deploy-with-secrets.sh` — multi-provider secret provisioning and deployment (Vault, GSM, GCP-KMS, manual)
- `docker-compose.postgres-exporter.yml` — postgres_exporter service
- `monitoring/prometheus.yml` — includes `postgres_exporter` job
- `.env` — provisioned atomically on remote (permissions 600)
- Immutable audit trail: git commits + `logs/deploy-with-secrets-*.jsonl`

## Verification Commands (copyable)
# Check exporter metrics on host
curl -s http://192.168.168.42:9187/metrics | head -n 20

# Check Prometheus targets
curl -s http://192.168.168.42:19090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="postgres_exporter")'

# Check Postgres logs for malformed packets
ssh akushnir@192.168.168.42 'cd /home/akushnir/self-hosted-runner && docker-compose -f docker-compose.phase6.yml logs --tail=200 database | grep "invalid length of startup packet" || echo "No malformed packets"'

## Deployment Commands (operators)
# Vault mode (production)
# Authenticate using your operator credential store and **do not paste tokens into files**.
# Example operator flow (do this in your secure shell/session):
#   Authenticate to Vault using your secure method, then run the deploy script:
#   VAULT_ADDR=https://vault.example.com bash scripts/deploy-with-secrets.sh --mode vault

# GSM mode
# Set `GOOGLE_APPLICATION_CREDENTIALS` securely in your environment (do not commit credentials):
#   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
#   bash scripts/deploy-with-secrets.sh --mode gsm

# Manual mode (testing/emergency)
# Use only for testing or emergency; avoid committing secrets to repo.
export POSTGRES_DSN='postgresql://portal_user:pass@database:5432/portal_db?sslmode=disable'
bash scripts/deploy-with-secrets.sh --mode manual

## Post-Deployment Notes
- All secrets MUST be provided via the chosen secret manager; never commit `.env` to git.
- The infrastructure uses direct SSH + docker-compose; no GitHub Actions or PR-based releases.
- Audit trail: commits pushed to `main` and JSONL logs in `logs/` directory.

## Monitoring & Next Steps
- Monitor Prometheus target health and Postgres logs for 24–48 hours.
- Consider adding `redis_exporter` and `node_exporter` as follow-ups.
- Schedule credential rotation automation (daily/weekly) using Vault/GSM cronjobs or orchestrator.
