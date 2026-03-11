# Canonical Secrets: End-to-End Deployment Guide

This guide orchestrates the complete canonical secrets deployment using the bootstrap automation.

## Quick Start (One Command)

On the approved deployment host (192.168.168.42):

```bash
# Fetch the branch and run the end-to-end bootstrap
git fetch origin canonical-secrets-impl-1773247600
git checkout canonical-secrets-impl-1773247600
bash scripts/deploy/bootstrap-canonical-deploy.sh
```

This single command performs:
1. ✅ Systemd service deployment
2. ✅ Health checks
3. ✅ Integration test suite
4. ✅ Post-deployment validation
5. ✅ Monitoring setup (Prometheus)

**Execution time:** ~2-3 minutes  
**Output:** Full deployment report with validation results

## Detailed Deployment Steps

### Step 1: Bootstrap Deployment

```bash
# Full deployment with all defaults
bash scripts/deploy/bootstrap-canonical-deploy.sh

# Skip tests (faster deployment)
bash scripts/deploy/bootstrap-canonical-deploy.sh --no-tests

# Skip monitoring setup
bash scripts/deploy/bootstrap-canonical-deploy.sh --no-monitoring

# Specify custom branch
bash scripts/deploy/bootstrap-canonical-deploy.sh --branch my-branch
```

**Output files:**
- `/tmp/canonical_deploy_<timestamp>.log` — Full deployment logs
- `/tmp/deployment_report_<timestamp>.json` — Deployment report

### Step 2: Post-Deployment Validation

```bash
# Run comprehensive validation (10 checkspoints)
bash scripts/test/post_deploy_validation.sh

# Validate specific endpoint
bash scripts/test/post_deploy_validation.sh --endpoint http://custom-host:8000
```

**Validation checks:**
- ✓ API reachability
- ✓ Health endpoint structure
- ✓ Provider resolution
- ✓ Credentials endpoint
- ✓ Migrations endpoint
- ✓ Audit endpoint
- ✓ Service logs
- ✓ Environment configuration
- ✓ Service enablement
- ✓ Service running status

**Output:** JSONL validation report (`/tmp/post_deploy_validation_<timestamp>.jsonl`)

### Step 3: Configure Monitoring

```bash
# Generate Grafana dashboard JSON (can be imported)
bash scripts/monitoring/generate_grafana_dashboard.sh

# Generate Prometheus alert rules and deploy
sudo tee /etc/prometheus/rules/canonical-secrets.yml < deploy/prometheus-alert-rules.yml
sudo systemctl restart prometheus
```

**Alerting rules configured:**
- `CanonicalSecretsHighLatency` — Response time > 500ms
- `CanonicalSecretsUnhealthy` — Service down
- `CanonicalSecretsProviderFailover` — Failover event
- `CanonicalSecretsMigrationErrors` — Migration failures
- `CanonicalSecretsAuditWriteFailure` — Audit log failure (critical)
- `CanonicalSecretsKMSError` — KMS encryption error (critical)

### Step 4: Verify Service

```bash
# Check service status
sudo systemctl status canonical-secrets-api.service

# Follow logs in real-time
sudo journalctl -u canonical-secrets-api.service -f

# Test health endpoint
curl http://localhost:8000/api/v1/secrets/health | jq

# Test provider resolution
curl http://localhost:8000/api/v1/secrets/resolve | jq

# Run full smoke tests
bash scripts/test/smoke_tests_canonical_secrets.sh

# Run full integration test harness
bash scripts/test/integration_test_harness.sh
```

### Step 5: Push Notifications

After deployment succeeds, notify stakeholders:

```bash
# Update GitHub issue with deployment status
gh issue comment <issue_number> --body "Deployment successful! Service running at http://localhost:8000/api/v1/secrets/health"

# Close deployment issue
gh issue close <issue_number>
```

## Environment Configuration

Before deployment, ensure `/etc/canonical_secrets.env` is populated:

```bash
sudo nano /etc/canonical_secrets.env
```

Required settings:
```env
VAULT_ADDR=http://vault.internal:8200
VAULT_TOKEN=<token>
ENVIRONMENT=production

# Optional: GCP/AWS/Azure credentials
GOOGLE_APPLICATION_CREDENTIALS=/opt/canonical-secrets/gcp-sa-key.json
AWS_REGION=us-east-1
AZURE_SUBSCRIPTION_ID=<id>
```

## Idempotency & No-Ops

All scripts are designed to be **idempotent** and **hands-off**:

- ✅ Running bootstrap multiple times is safe (systemd service re-created if needed)
- ✅ Health checks retry automatically on transient failures
- ✅ Tests timeout gracefully and report results
- ✅ Monitoring setup skips already-configured providers
- ✅ No manual intervention required

## Troubleshooting

### Service fails to start
```bash
# Check systemd logs
sudo journalctl -u canonical-secrets-api.service -n 50

# Check environment file
sudo cat /etc/canonical_secrets.env

# Verify Vault connectivity
curl $VAULT_ADDR/v1/sys/health
```

### Health check fails
```bash
# Verify port is listening
lsof -i :8000

# Check firewall rules
sudo ufw status
sudo iptables -L

# Manual health check
curl -v http://localhost:8000/api/v1/secrets/health
```

### Tests timeout
- Increase timeout in `scripts/test/integration_test_harness.sh`
- Check for network latency to external providers
- Verify Vault, GSM, AWS, Azure are accessible

### Logs not appearing
```bash
# Check log directory permissions
sudo ls -la /var/log/canonical-secrets/

# Verify logrotate config
sudo cat /etc/logrotate.d/canonical-secrets
```

## Rollback

If deployment fails, rollback to previous state:

```bash
# List previous commits
git log --oneline -10

# Checkout previous branch/commit
git checkout <previous-commit>

# Re-run bootstrap (idempotent)
bash scripts/deploy/bootstrap-canonical-deploy.sh
```

## Next Steps

1. **Deploy to staging first:** Test on non-production host
2. **Run full validation:** Use `post_deploy_validation.sh`
3. **Monitor alerts:** Watch Prometheus/Grafana dashboards
4. **Notify ops team:** Update runbooks with service commands
5. **Plan production rollout:** Use phased deployment strategy

## References

- [CANONICAL_SECRETS_IMPLEMENTATION.md](../CANONICAL_SECRETS_IMPLEMENTATION.md) — Architecture & implementation details
- [DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md](../DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md) — Detailed procedures
- [CANONICAL_SECRETS_DEPLOYMENT_SIGN_OFF.md](../CANONICAL_SECRETS_DEPLOYMENT_SIGN_OFF.md) — Sign-off & compliance
- [backend/README.md](../backend/README.md) — Backend service docs
- [scripts/](../scripts/) — All automation scripts
