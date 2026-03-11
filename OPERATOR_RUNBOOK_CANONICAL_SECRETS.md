# Canonical Secrets — Quick Reference & Operator Runbook

**This document provides quick commands and runbook for daily operations.**

---

## Quick Deployment (30 seconds)

```bash
# One-line deployment on approved host
git fetch origin canonical-secrets-impl-1773247600 && \
git checkout canonical-secrets-impl-1773247600 && \
sudo bash scripts/deploy/systemd-deploy.sh
```

---

## Service Status & Logs

### Check Service
```bash
# Status
sudo systemctl status canonical-secrets-api.service

# Is it running?
sudo systemctl is-active canonical-secrets-api.service

# Is it enabled for auto-start?
sudo systemctl is-enabled canonical-secrets-api.service

# View live logs
sudo journalctl -u canonical-secrets-api.service -f

# View last 50 lines
sudo journalctl -u canonical-secrets-api.service -n 50
```

### Service Control
```bash
# Start service
sudo systemctl start canonical-secrets-api.service

# Stop service
sudo systemctl stop canonical-secrets-api.service

# Restart service (apply env file changes)
sudo systemctl restart canonical-secrets-api.service

# Reload configuration without restart
sudo systemctl reload canonical-secrets-api.service
```

---

## API Health & Testing

### Health Check
```bash
# JSON response
curl http://localhost:8000/api/v1/secrets/health | jq

# Simple text
curl -s http://localhost:8000/api/v1/secrets/health | jq '.status'
```

### Provider Validation
```bash
# Check which provider is primary
curl http://localhost:8000/api/v1/secrets/resolve | jq

# Check provider health
curl http://localhost:8000/api/v1/secrets/health | jq '.providers'
```

### Test Endpoints
```bash
# List all credentials
curl http://localhost:8000/api/v1/secrets/credentials | jq

# List migrations
curl http://localhost:8000/api/v1/secrets/migrations | jq

# View audit log
curl http://localhost:8000/api/v1/secrets/audit | jq
```

---

## Test Suites

### Run All Tests
```bash
# Full integration harness (10+ minutes)
bash scripts/test/integration_test_harness.sh

# Smoke tests only (2 minutes)
bash scripts/test/smoke_tests_canonical_secrets.sh

# Post-deployment validation (1 minute)
bash scripts/test/post_deploy_validation.sh

# Audit immutability verification
bash scripts/security/verify_audit_immutability.sh
```

---

## Credential Management

### Update Credentials File
```bash
# Edit environment variables
sudo nano /etc/canonical_secrets.env

# Restart to apply changes
sudo systemctl restart canonical-secrets-api.service
```

### Rotate Vault Token
```bash
# 1. Generate new token in Vault
vault token create -ttl=8760h

# 2. Update environment file
sudo nano /etc/canonical_secrets.env
# Set VAULT_TOKEN=<new-token>

# 3. Restart service
sudo systemctl restart canonical-secrets-api.service

# 4. Verify health
curl http://localhost:8000/api/v1/secrets/health
```

### Rotate Database Password (Example)
```bash
# 1. Write new password to Vault
vault kv put secret/prod/db_password password=$(openssl rand -base64 32)

# 2. Service fetches fresh on next request (ephemeral!)
curl http://localhost:8000/api/v1/secrets/credentials?name=prod/db_password

# 3. Update application configuration (out of band)
# Applications must reload config; service restart not needed
```

---

## Deployment Changes & Recovery

### View Deployment History
```bash
# Check branch commits
git log --oneline origin/canonical-secrets-impl-1773247600 -10

# Current commit on service
git rev-parse HEAD

# Compare with remote
git diff HEAD origin/canonical-secrets-impl-1773247600
```

### Rollback to Previous Version
```bash
# 1. Stop service
sudo systemctl stop canonical-secrets-api.service

# 2. Check out previous commit
git checkout <previous-commit-hash>

# 3. Re-run deployment (idempotent)
sudo bash scripts/deploy/systemd-deploy.sh

# 4. Verify
curl http://localhost:8000/api/v1/secrets/health
```

### Emergency Stop & Manual Recovery
```bash
# Emergency stop everything
sudo systemctl stop canonical-secrets-api.service

# Verify it's stopped
sudo systemctl is-active canonical-secrets-api.service

# Check for hanging processes
ps aux | grep canonical_secrets_api | grep -v grep

# Kill stubborn processes (if needed)
sudo pkill -9 -f canonical_secrets_api

# Start fresh
sudo systemctl start canonical-secrets-api.service
```

---

## Monitoring & Alerts

### Prometheus Metrics
```bash
# Query Prometheus for API response time
curl 'http://prometheus:9090/api/v1/query?query=canonical_secrets_api_response_time_ms'

# Check provider health metric
curl 'http://prometheus:9090/api/v1/query?query=canonical_secrets_provider_health'
```

### Setup Grafana Dashboard
```bash
# Generate dashboard JSON
bash scripts/monitoring/generate_grafana_dashboard.sh

# Output: /tmp/canonical_secrets_dashboard.json
# Import into Grafana via: Settings > Dashboards > Import JSON
```

### Alert Rules
```bash
# Verify Prometheus alert rules are loaded
curl http://prometheus:9090/api/v1/rules | jq '.data.groups[] | select(.name=="canonical_secrets_alerts")'

# Common alerts:
# - CanonicalSecretsHighLatency (>500ms)
# - CanonicalSecretsUnhealthy (service down)
# - CanonicalSecretsProviderFailover (failover detected)
# - CanonicalSecretsMigrationErrors (migration failures)
# - CanonicalSecretsAuditWriteFailure (audit trail issue)
# - CanonicalSecretsKMSError (encryption error)
```

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| Service won't start | `sudo journalctl -u canonical-secrets-api.service -n 50` |
| Port 8000 already in use | `sudo lsof -i :8000; sudo kill <PID>` |
| VAULT_TOKEN expired | Update `/etc/canonical_secrets.env` + `sudo systemctl restart canonical-secrets-api.service` |
| Health check fails | Verify Vault at `curl $VAULT_ADDR/v1/sys/health` |
| Slow API response | Check provider health: `curl http://localhost:8000/api/v1/secrets/health` |
| Audit log write fails | Check `/var/log/canonical-secrets/` permissions |
| KMS encryption error | Verify KMS keys in cloud provider (GCP/AWS/Azure) |
| Migration stuck | View migration status: `curl http://localhost:8000/api/v1/secrets/migrations` |

---

## Emergency Procedures

### Immediate Credential Rotation (No Downtime)
```bash
# 1. Write new secret directly to Vault
vault kv put secret/prod/api_key key=$(openssl rand -hex 32)

# 2. Service fetches fresh on next request
# (No restart needed; ephemeral access)
curl http://localhost:8000/api/v1/secrets/credentials?name=prod/api_key

# 3. Clients must reload config (as needed)
```

### Provider Failover (Automatic)
```bash
# If Vault is down, service automatically fails over to GSM, then AWS, then Azure
# No restart needed; automatic detection

# Check current provider
curl http://localhost:8000/api/v1/secrets/resolve | jq '.primary_provider'

# Restore Vault, automatic re-prioritization occurs
```

### Full Service Restore from Backup
```bash
# 1. Stop service
sudo systemctl stop canonical-secrets-api.service

# 2. Restore secrets from backup (if applicable)
# Ask: Are secrets backed up offsite? (Check Vault disaster recovery)

# 3. Reinstall service
sudo bash scripts/deploy/systemd-deploy.sh

# 4. Verify
curl http://localhost:8000/api/v1/secrets/health
```

---

## References

- Full deployment guide: [DEPLOYMENT_BOOTSTRAP_GUIDE.md](./DEPLOYMENT_BOOTSTRAP_GUIDE.md)
- Operations procedures: [DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md](./DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md)
- Implementation details: [CANONICAL_SECRETS_IMPLEMENTATION.md](./CANONICAL_SECRETS_IMPLEMENTATION.md)
- Architecture & sign-off: [CANONICAL_SECRETS_DEPLOYMENT_SIGN_OFF.md](./CANONICAL_SECRETS_DEPLOYMENT_SIGN_OFF.md)

---

**Keep this document handy for daily operations and incident response.**
