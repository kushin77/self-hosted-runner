# Deployment Readiness Checklist

**Canonical Secrets API — Production Deployment**  
**Date:** March 11, 2026  
**Status:** ✅ READY FOR DEPLOYMENT  
**Branch:** `canonical-secrets-impl-1773247600`

---

## Pre-Flight Checklist (Operator)

Before beginning deployment, verify these prerequisites:

### Infrastructure
- [ ] Approved deployment host (192.168.168.42) is accessible
- [ ] Host has systemd and Python 3.11+
- [ ] Docker is installed (if using docker-compose path)
- [ ] Git is installed and repository is cloned
- [ ] Vault is reachable at `$VAULT_ADDR` (typically http://vault.internal:8200)

### Credentials & Secrets
- [ ] Vault token obtained and ready (will be set in `/etc/canonical_secrets.env`)
- [ ] GCP credentials (JSON key file) available for GSM failover (optional)
- [ ] AWS credentials available for Secrets Manager failover (optional)
- [ ] Azure credentials available for Key Vault failover (optional)
- [ ] KMS keys configured in each cloud provider (if using failover)

### Network
- [ ] Port 8000 available on host (FastAPI service)
- [ ] Reverse proxy/firewall configured for external access (if needed)
- [ ] DNS or `/etc/hosts` configured for service discovery

### Monitoring (Optional)
- [ ] Prometheus is running (needed for alerts)
- [ ] Grafana is available (needed for dashboards)
- [ ] PagerDuty/Slack webhook URLs ready (for alerting)

---

## Deployment Steps (Automated)

### Step 1: Prepare Branch

```bash
cd /path/to/self-hosted-runner
git fetch origin canonical-secrets-impl-1773247600
git checkout canonical-secrets-impl-1773247600
git pull origin HEAD
```

### Step 2: Run End-to-End Bootstrap

**Single command deploys everything:**

```bash
sudo bash scripts/deploy/systemd-deploy.sh
```

**What this does:**
1. Creates `secretsd` system user
2. Installs files to `/opt/canonical-secrets`
3. Creates Python virtual environment
4. Installs dependencies
5. Creates `/etc/canonical_secrets.env` (with placeholders)
6. Deploys systemd unit
7. Enables and starts service
8. Runs health checks

**Expected output:**
```
✅ Service enabled and started
Deployment Complete!
Service: canonical-secrets-api
Status: ✅ RUNNING
Health: http://localhost:8000/api/v1/secrets/health
```

### Step 3: Configure Credentials

Edit the environment file:

```bash
sudo nano /etc/canonical_secrets.env
```

**Required fields:**
```env
VAULT_ADDR=http://vault.internal:8200
VAULT_TOKEN=<your-vault-token>
ENVIRONMENT=production
```

**Optional fields (for cloud failover):**
```env
GOOGLE_APPLICATION_CREDENTIALS=/opt/canonical-secrets/gcp-sa-key.json
AWS_REGION=us-east-1
AZURE_SUBSCRIPTION_ID=<subscription-id>
```

### Step 4: Restart Service

```bash
sudo systemctl restart canonical-secrets-api.service
```

### Step 5: Verify Deployment

#### Quick Health Check
```bash
curl http://localhost:8000/api/v1/secrets/health | jq
```

#### Full Validation
```bash
bash scripts/test/post_deploy_validation.sh
```

#### Run All Integration Tests
```bash
bash scripts/test/integration_test_harness.sh
```

---

## Post-Deployment Actions

### Monitoring Setup (if not auto-configured)

```bash
# Deploy Prometheus alert rules
sudo cp deploy/prometheus-alert-rules.yml /etc/prometheus/rules/
sudo systemctl restart prometheus

# Generate Grafana dashboard
bash scripts/monitoring/generate_grafana_dashboard.sh

# Import the JSON output into Grafana
# Settings > Dashboards > Import JSON
```

### Service Verification

```bash
# Check service status
sudo systemctl status canonical-secrets-api.service

# Follow logs
sudo journalctl -u canonical-secrets-api.service -f

# Check specific endpoints
curl http://localhost:8000/api/v1/secrets/resolve | jq
curl http://localhost:8000/api/v1/secrets/audit | jq
```

### Enable Notifications

```bash
# Update GitHub issue with deployment confirmation
gh issue comment 2594 --body "✅ Deployment successful on $(hostname)! Service running at http://localhost:8000/api/v1/secrets/health"
```

---

## Rollback Procedure

If deployment fails or needs rollback:

```bash
# Stop the service
sudo systemctl stop canonical-secrets-api.service

# Checkout previous commit
git checkout <previous-commit-hash>

# Re-run deployment (idempotent; safe to retry)
sudo bash scripts/deploy/systemd-deploy.sh
```

---

## Troubleshooting

### Service Fails to Start

Check logs:
```bash
sudo journalctl -u canonical-secrets-api.service -n 50 -e
```

Common issues:
- **VAULT_TOKEN not set:** Edit `/etc/canonical_secrets.env` with valid token
- **Port 8000 in use:** Check with `lsof -i :8000` and kill conflicting process
- **Permissions error:** Verify `/opt/canonical-secrets` is owned by `secretsd:secretsd`

### Health Check Fails

```bash
# Manual health check
curl -v http://localhost:8000/api/v1/secrets/health

# Check Vault connectivity
curl -v $VAULT_ADDR/v1/sys/health

# Check logs for specific errors
sudo journalctl -u canonical-secrets-api.service | grep ERROR
```

### Tests Timeout

- Increase timeout in `scripts/test/integration_test_harness.sh`
- Check network connectivity to providers (Vault, GCP, AWS, Azure)
- Verify KMS keys are accessible

---

## Deployment Validation Results

All pre-deployment checks completed:

| Check | Status |
|-------|--------|
| Provider hierarchy | ✅ Implemented (Vault → GSM → AWS → Azure) |
| Migration orchestrator | ✅ Idempotent migration with integrity checks |
| FastAPI backend | ✅ Built and pushed (image: `canonical-secrets-api:20260311`) |
| Portal UI | ✅ Portal component ready (requires separate build) |
| Smoke tests | ✅ 5 tests (health, resolution, ephemeral, idempotency, sync) |
| Audit immutability | ✅ Hash-chain verification script ready |
| Systemd deployment | ✅ Hands-off playbook ready |
| Docker deployment | ✅ Dockerfile + docker-compose template ready |
| Monitoring | ✅ Prometheus rules + Grafana dashboard generator ready |
| Documentation | ✅ Complete deployment procedures + bootstrap guide |

---

## Deployment Sign-Off

**Implementation:** ✅ Complete  
**Testing:** ✅ Complete  
**Documentation:** ✅ Complete  
**Monitoring:** ✅ Ready  
**Branch:** ✅ Pushed to `origin/canonical-secrets-impl-1773247600`  

**Ready for production deployment.**

---

## Support & Escalation

**Deployed service:** http://localhost:8000/api/v1/secrets  
**Documentation:** See [DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md](./DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md)  
**Emergency contact:** See on-call roster  
**Rollback:** Follow procedures in this document  

---

For any issues during deployment, refer to:
- [DEPLOYMENT_BOOTSTRAP_GUIDE.md](./DEPLOYMENT_BOOTSTRAP_GUIDE.md)
- [DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md](./DEPLOYMENT_PROCEDURES_CANONICAL_SECRETS.md)
- [CANONICAL_SECRETS_IMPLEMENTATION.md](./CANONICAL_SECRETS_IMPLEMENTATION.md)
