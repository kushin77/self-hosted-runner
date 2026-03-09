# Operator Runbook: Direct Deployment Only

**Effective Date:** 2026-03-09  
**Status:** ACTIVE  
**Model:** Direct deployment to worker node (zero CI/CD, zero workflows, zero managed runners)

---

## Overview

This repository operates under a **direct-deployment-only** model:
- **No GitHub Actions workflows** active on `main` branch.
- **No managed runners** registered or polled by GitHub.
- **All deployments** performed directly to the approved worker node at `192.168.168.42`.
- **All credentials** fetched at runtime via GSM/Vault/KMS; never embedded.
- **All operations** immutable, ephemeral, idempotent, and automatically scheduled on the worker node itself.

---

## Who Can Deploy

**Authorized operators only** — verified by SSH access to `192.168.168.42` using the `deploy` account or an Ops-specified account.

---

## Deployment Process (Quick Reference)

### 1. Open a Deployment Issue

```bash
gh issue create \
  --repo kushin77/self-hosted-runner \
  --title "Deploy: <brief description>" \
  --label ops,deployment \
  --body "Change: <what is being deployed>
  
Validation: <how locally tested>

Rollback: <how to revert if needed>

Worker: 192.168.168.42
Deployer: $(whoami)
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
```

### 2. Prepare Deployment Bundle Locally

```bash
# Run all local tests
bash tests/test-provisioning-integration.sh

# Build deployment bundle (tar.gz)
tar --exclude=.git --exclude=node_modules --exclude=venv -czf deployment-bundle.tar.gz .
sha256sum deployment-bundle.tar.gz > deployment-bundle.tar.gz.sha256
```

### 3. Transfer to Worker Node

```bash
# Copy bundle and checksum to worker
scp deployment-bundle.tar.gz deployment-bundle.tar.gz.sha256 deploy@192.168.168.42:/tmp/

# Verify checksum on worker
ssh deploy@192.168.168.42 'cd /tmp && sha256sum -c deployment-bundle.tar.gz.sha256'
```

### 4. Deploy on Worker

```bash
ssh deploy@192.168.168.42 bash <<'EOF'
  set -e
  cd /tmp
  tar -xzf deployment-bundle.tar.gz -C /opt/app/
  /opt/app/deploy.sh -v
  echo "✓ Deployment complete at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
```

### 5. Update Deployment Issue

```bash
gh issue comment <issue-number> --body "**Deployed:** 
- Commit: $(git rev-parse HEAD)
- Bundle SHA256: $(cat deployment-bundle.tar.gz.sha256 | awk '{print $1}')
- Deployer: $(whoami)
- Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Status: ✓ SUCCESS
- Audit: See logs/deployment-provisioning-audit.jsonl on worker"

gh issue close <issue-number>
```

---

## Deployment Scripts (On Worker)

All scripts below run **in isolation** on the worker; they are idempotent and safe to run multiple times.

### `./deploy.sh`

Main deployment entry point.

```bash
ssh deploy@192.168.168.42 /opt/app/deploy.sh -v
```

**Idempotency:** Uses lock files in `/var/lock/deployment-*.lock`.  
**Audit:** Writes to `logs/deployment-provisioning-audit.jsonl` (append-only).

### Credential Provisioning (Automatic)

When `deploy.sh` runs, it will automatically:
1. Fetch credentials from GSM/Vault/KMS using environment-specific roles.
2. Provision credentials to `.env.deployment`, GitHub secrets, or systemd env files.
3. Log all actions to the audit trail.

**Manual provisioning** (if needed):

```bash
ssh deploy@192.168.168.42 bash <<'EOF'
  make -f /opt/app/Makefile.provisioning provision-fields
  make -f /opt/app/Makefile.provisioning verify-provisioning
  cat /opt/app/logs/deployment-provisioning-audit.jsonl | tail -5
EOF
```

---

## Credential Sources & Fallback Chain

Scripts attempt credentials in this order:

1. **GitHub Secrets** (if running in a GitHub Actions env — NOT in use now)
2. **Google Secret Manager (GSM)** — `gcloud secrets access <secret> --project=gcp-eiq`
3. **HashiCorp Vault** — `curl -s $VAULT_ADDR/v1/auth/jwt/login` + `curl -s $VAULT_ADDR/v1/secret/data/deployment/<field>`
4. **AWS Secrets Manager** — via IAM role OIDC: `aws secretsmanager get-secret-value --secret-id <field>`

For each provider, the script uses environment-specific credentials (dev/stage/prod roles).

---

## Environment Variables (On Worker)

Set these on the worker before running deployments:

```bash
export VAULT_ADDR="https://vault.example.internal:8200"
export VAULT_ROLE="deployment-${ENVIRONMENT}"  # e.g., deployment-prod
export AWS_ROLE_TO_ASSUME="arn:aws:iam::123456789012:role/DeploymentRole-${ENVIRONMENT}"
export GCP_WORKLOAD_IDENTITY_PROVIDER="projects/123456789/locations/global/workloadIdentityPools/github/providers/github"
export ENVIRONMENT="prod"  # or dev, stage
```

Or load from `.env.deployment` (created by auto-provisioning):

```bash
source /opt/app/.env.deployment
```

---

## Immutability & Audit Trail

Every deployment is logged to an append-only JSONL file:

```bash
ssh deploy@192.168.168.42 tail -20 /opt/app/logs/deployment-provisioning-audit.jsonl
```

Example entry:

```json
{"timestamp":"2026-03-09T10:45:32Z","action":"provision_field","field":"VAULT_ADDR","source":"gsm","status":"success","deployer":"deploy"}
```

**Note:** This file is **never** truncated; operators can retrieve the full deployment history.

---

## Rollback

If a deployment fails or needs to be rolled back:

1. **Review audit trail** on the worker to identify what was deployed.
2. **Prepare a rollback bundle** with the previous known-good state.
3. **Follow the deployment process (steps 1–5)** with `deploy.sh --rollback` or manual restoration.

Example:

```bash
ssh deploy@192.168.168.42 /opt/app/deploy.sh --rollback
```

---

## Health Checks & Monitoring

### Manual Health Check

```bash
ssh deploy@192.168.168.42 make -f /opt/app/Makefile.provisioning verify-provisioning
```

### Scheduled Health Checks (On Worker)

The worker node runs a local daemon that performs health checks every 30 minutes:

```bash
ssh deploy@192.168.168.42 systemctl status deployment-health-check
ssh deploy@192.168.168.42 journalctl -u deployment-health-check -n 20
```

### Provisioning Audit Trail

View the most recent provisioning actions:

```bash
ssh deploy@192.168.168.42 bash <<'EOF'
  echo "Recent provisioning events:"
  tail -10 /opt/app/logs/deployment-provisioning-audit.jsonl | jq -r '.timestamp, .action, .field, .status'
EOF
```

---

## Troubleshooting

### SSH Connection Fails

```bash
# Verify auth and connectivity
ssh -v deploy@192.168.168.42 echo "Connected"

# Check runner configuration
ssh deploy@192.168.168.42 cat /opt/app/.env.deployment | grep -E "VAULT|AWS|GCP"
```

### Credentials Not Provisioned

```bash
# Check if providers are reachable
ssh deploy@192.168.168.42 bash <<'EOF'
  [ -n "$VAULT_ADDR" ] && curl -s -I "$VAULT_ADDR/v1/sys/health" | head -1 || echo "VAULT_ADDR not set"
  gcloud secrets list --project=gcp-eiq | head -5 || echo "GSM access failed"
  aws sts get-caller-identity 2>&1 | head -1 || echo "AWS access failed"
EOF
```

### Deployment Bundle Corrupt

```bash
# Verify checksum before and after transfer
# On deployer machine:
sha256sum deployment-bundle.tar.gz

# On worker (via SSH):
sha256sum -c deployment-bundle.tar.gz.sha256
```

### Manual Rollback

```bash
ssh deploy@192.168.168.42 bash <<'EOF'
  cd /opt/app
  git status
  git log --oneline -5  # Review recent commits
  git revert <commit-sha>  # or git reset --hard <known-good-sha>
  /opt/app/deploy.sh
EOF
```

---

## Operators & Access

### Require Access To

- SSH key pair (private key) for `deploy@192.168.168.42`
- GSM project with secret accessor role (if using GSM)
- Vault JWT auth or AppRole credentials (if using Vault)
- AWS IAM role assuming (if using AWS Secrets Manager)
- GCP Workload Identity Provider (if using GCP)

### Request Access

Open an issue tagged `ops` and `access-request` with:

```
Requestor: <your name>
Role: <deployment operator | on-call | deployer>
Systems: GSM, Vault, AWS, GCP (choose which)
Environment: dev, stage, prod
Duration: <temporary (until date) | permanent>
```

---

## Runbook Updates

This runbook is part of the repository. To update:

1. Edit this file locally.
2. Commit to `main` (direct push as authorized operator).
3. Notify the ops team in an issue or Slack channel.

---

## Contact

- **Ops Issues:** Open an issue labeled `ops`.
- **Emergency Access:** Post in #ops Slack channel or email ops@example.com.
- **Security/Credentials:** Post in #security Slack or email security@example.com.

---

**Last Updated:** 2026-03-09  
**Next Review:** 2026-04-09
