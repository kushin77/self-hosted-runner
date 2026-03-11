# Canonical Secrets Deployment Procedures

## Overview
Hands-off, direct-deployment procedures for the canonical secrets API. No GitHub Actions or PR-based releases.

## Prerequisites
- Python 3.11+
- Docker (for container deployment) or systemd (for service deployment)
- systemctl (for systemd-based deployment)
- Vault, GSM, AWS Secrets Manager, Azure Key Vault (or at least one provider)
- KMS keys configured for each provider

## Deployment Options

### Option 1: Systemd Service (Recommended for Single Host)

```bash
# 1. Prepare repository on target host
git clone <repo> && cd self-hosted-runner

# 2. Run deployment playbook (hands-off)
sudo bash scripts/deploy/systemd-deploy.sh

# 3. Update environment file with credentials
sudo nano /etc/canonical_secrets.env
# Set VAULT_TOKEN, GCP credentials, AWS keys, Azure credentials, etc.

# 4. Restart service to apply new credentials
sudo systemctl restart canonical-secrets-api.service

# 5. Verify health
curl http://localhost:8000/api/v1/secrets/health
```

### Option 2: Docker Compose (for Multi-Service Stack)

```bash
# 1. Build image locally or pull from registry
export DOCKER_REGISTRY=registry.example.com/org
export IMAGE_TAG=20260311
bash scripts/deploy/build_and_push_images.sh

# 2. Deploy stack
export DOCKER_REGISTRY=registry.example.com/org
docker compose -f deploy/docker-compose.secrets.yml up -d --remove-orphans

# 3. Verify deployment
docker compose -f deploy/docker-compose.secrets.yml ps
curl http://localhost:8000/api/v1/secrets/health
```

### Option 3: Kubernetes (for Multi-Region Failover)

See `deploy/kubernetes/canonical-secrets.yaml` for k8s manifests (includes:
- Deployment with rolling updates
- ConfigMap for non-secret configuration
- Secret for environment variables (managed by Vault or external secret operator)
- Service + Ingress for multi-region access
- NetworkPolicy for security isolation

```bash
kubectl apply -f deploy/kubernetes/canonical-secrets.yaml
```

## Post-Deployment Validation

### Run Smoke Tests
```bash
bash scripts/test/smoke_tests_canonical_secrets.sh
```

### Run Full Integration Tests
```bash
bash scripts/test/integration_test_harness.sh
```

### Verify Audit Immutability
```bash
bash scripts/security/verify_audit_immutability.sh
```

## Operations

### Check Service Status
**Systemd:**
```bash
sudo systemctl status canonical-secrets-api.service
journalctl -u canonical-secrets-api.service -f
```

**Docker Compose:**
```bash
docker compose -f deploy/docker-compose.secrets.yml logs canonical-secrets-api -f
```

**Kubernetes:**
```bash
kubectl logs deployment/canonical-secrets-api -f
```

### Rotate Credentials
1. Update secret in Vault or local provider
2. Service fetches fresh secret on next request (ephemeral access)
3. No cache invalidation needed

### Failover Between Providers
1. Health check automatically detects provider unavailability
2. Automatic failover to next provider in hierarchy (Vault → GSM → AWS → Azure)
3. Manual override via API: `POST /api/v1/secrets/resolve?preferred_provider=gsm`

### Backup & Recovery
```bash
# Backup all secrets from Vault
bash scripts/secrets/canonical-migration-orchestrator.sh backup

# Restore from backup
bash scripts/secrets/canonical-migration-orchestrator.sh restore
```

## Security Hardening

### KMS Encryption
All sensitive operations (create, rotate, migrate) use KMS encryption:
- Vault: native KMS integration
- GCP: Cloud KMS
- AWS: KMS key policies enforced
- Azure: Key Vault native

### Audit Trail
- Immutable append-only JSONL logs with hash chain
- Each operation:
  - Timestamp (UTC)
  - Operation type and actor
  - Secret name (non-secret)
  - KMS key ID used
  - Result (success/failure)
  - Policy violations (if any)

### Network Security
- Firewall: restrict to API consumers only
- TLS 1.3 enforcement (reverse proxy)
- Private IPs recommended (not internet-facing)
- NetworkPolicy (Kubernetes)

### IAM / RBAC
- Least privilege: service accounts per role
- Vault: AppRole authentication (no token hardcoding)
- GCP: Workload Identity (Kubernetes)
- AWS: IRSA (IAM Roles for Service Accounts)
- Azure: Managed Identity

## Troubleshooting

### Service won't start
```bash
# Systemd
sudo systemctl status canonical-secrets-api.service
journalctl -u canonical-secrets-api.service -n 50

# Docker
docker logs canonical-secrets-api
```

### Health check fails
```bash
# Check if service is listening
lsof -i :8000
# or
netstat -an | grep 8000

# Check Vault connectivity
curl -v http://vault.internal:8200/v1/sys/health
```

### Authentication failure (Vault)
- Verify VAULT_TOKEN is set and valid
- Check AppRole credentials (if using AppRole)
- Verify Vault policy allows KV operations

### Slow provider resolution
- Check provider health checks (should complete in <100ms)
- Verify network latency: `ping gsm.googleapis.com`
- Enable debug logging: `export DEBUG=1`

## Compliance & Auditing

All deployments are audited and logged:
1. Deployment timestamp and operator
2. Configuration changes (stored in git, branch protected)
3. Secret operations (Vault audit log, immutable trail)
4. Provider health checks (periodic; recorded)
5. Migration status (state file with checksums)

## Emergency Procedures

### Immediate Secret Rotations
```bash
# 1. Write new secret to Vault
vault kv put secret/prod/db_password value=<new_pass>

# 2. Service fetches fresh value (ephemeral; no cache)
curl http://localhost:8000/api/v1/secrets/credentials?name=prod/db_password

# 3. Applications must reload config (no app restart needed)
```

### Provider Outage (e.g., Vault down)
1. Automatic failover: API routes to next healthy provider (GSM)
2. No manual action needed
3. Once Vault is back, automatic re-prioritization

### Full Stack Rollback
```bash
# Restore from backup
git revert <commit-hash>
git push origin HEAD
# Re-deploy using new commit
bash scripts/deploy/systemd-deploy.sh
```

## Monitoring & Alerting

Key metrics to monitor:
- Service uptime (systemctl or k8s probes)
- API response time (< 100ms for health, < 500ms for fetch)
- Provider health status (all green)
- Audit log write latency (append-only constraint)
- Secret fetch pattern anomalies

Recommended tools:
- Prometheus + Grafana (metrics)
- ELK Stack (audit logs)
- Vault audit trail (provider operations)
- HashiCorp Sentinel (policy engine)

## References

- [Canonical Secrets Implementation](CANONICAL_SECRETS_IMPLEMENTATION.md)
- [Secrets Provider Hierarchy](../scripts/secrets/canonical-provider-hierarchy.sh)
- [Migration Orchestrator](../scripts/secrets/canonical-migration-orchestrator.sh)
- [API Documentation](../backend/canonical_secrets_api.py)
- [Portal Dashboard](../frontend/src/components/SecretsManagementDashboard.tsx)
