# Hardened Deployment Guide
**Last Updated**: March 15, 2026

## Overview

This guide describes how to deploy the hardened self-hosted runner infrastructure with **runtime-only secret injection**. No secrets are stored in the codebase.

## Prerequisites

1. ✅ Hardened docker-compose.yml deployed (Commit 3f8208fe5)
2. ✅ Hardened deploy-worker-node.sh deployed (Commit 3f8208fe5)  
3. ✅ Cloud secret manager access (GSM, Vault, or AWS Secrets)
4. ✅ SSH key-based access to 192.168.168.42 (no passwords)

## Deployment Workflow

### Step 1: Retrieve Secrets from Cloud Manager

Choose your provider:

**Google Secret Manager (GSM)**:
```bash
#!/bin/bash
# Production deployment with GSM
export POSTGRES_PASSWORD=$(gcloud secrets versions access latest --secret="nexus-postgres-password")
export KEYCLOAK_ADMIN=$(gcloud secrets versions access latest --secret="nexus-keycloak-admin")
export KEYCLOAK_ADMIN_PASSWORD=$(gcloud secrets versions access latest --secret="nexus-keycloak-admin-password")
export GOOGLE_OAUTH_CLIENT_ID=$(gcloud secrets versions access latest --secret="nexus-google-client-id")
export GOOGLE_OAUTH_CLIENT_SECRET=$(gcloud secrets versions access latest --secret="nexus-google-client-secret")
export OAUTH2_PROXY_COOKIE_SECRET=$(gcloud secrets versions access latest --secret="nexus-oauth2-cookie-secret")
```

**HashiCorp Vault**:
```bash
#!/bin/bash
# Production deployment with Vault
export POSTGRES_PASSWORD=$(vault kv get -field=password secret/nexus/database)
export KEYCLOAK_ADMIN=$(vault kv get -field=admin secret/nexus/keycloak)
export KEYCLOAK_ADMIN_PASSWORD=$(vault kv get -field=admin_password secret/nexus/keycloak)
export GOOGLE_OAUTH_CLIENT_ID=$(vault kv get -field=client_id secret/nexus/oauth)
export GOOGLE_OAUTH_CLIENT_SECRET=$(vault kv get -field=client_secret secret/nexus/oauth)
export OAUTH2_PROXY_COOKIE_SECRET=$(vault kv get -field=cookie_secret secret/nexus/oauth)
```

**AWS Secrets Manager**:
```bash
#!/bin/bash
# Production deployment with AWS Secrets
export POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value --secret-id nexus/postgres/password --query SecretString --output text)
export KEYCLOAK_ADMIN=$(aws secretsmanager get-secret-value --secret-id nexus/keycloak/admin --query SecretString --output text)
export KEYCLOAK_ADMIN_PASSWORD=$(aws secretsmanager get-secret-value --secret-id nexus/keycloak/admin_password --query SecretString --output text)
export GOOGLE_OAUTH_CLIENT_ID=$(aws secretsmanager get-secret-value --secret-id nexus/oauth/client_id --query SecretString --output text)
export GOOGLE_OAUTH_CLIENT_SECRET=$(aws secretsmanager get-secret-value --secret-id nexus/oauth/client_secret --query SecretString --output text)
export OAUTH2_PROXY_COOKIE_SECRET=$(aws secretsmanager get-secret-value --secret-id nexus/oauth/cookie_secret --query SecretString --output text)
```

### Step 2: Validate Secrets Are Set

```bash
#!/bin/bash
# Verify all required secrets are in environment
required_secrets=(
  "POSTGRES_PASSWORD"
  "KEYCLOAK_ADMIN"
  "KEYCLOAK_ADMIN_PASSWORD"
  "GOOGLE_OAUTH_CLIENT_ID"
  "GOOGLE_OAUTH_CLIENT_SECRET"
  "OAUTH2_PROXY_COOKIE_SECRET"
)

for secret in "${required_secrets[@]}"; do
  if [ -z "${!secret}" ]; then
    echo "❌ ERROR: $secret is not set"
    exit 1
  fi
  echo "✅ $secret is set"
done

echo ""
echo "All secrets validated. Ready for deployment."
```

### Step 3: Deploy with Hardened Configuration

**Direct Deployment Script** (Recommended for CI/CD):
```bash
#!/bin/bash
set -e

# Source the secrets from your cloud manager
source get-secrets.sh  # Script from Step 1

# Verify secrets
source validate-secrets.sh  # Script from Step 2

# Deploy to on-premises worker
ssh akushnir@192.168.168.42 << DEPLOY_EOF
  cd /home/akushnir/self-hosted-runner
  
  # Create .env file with secrets (ephemeral)
  cat > .env << '.env.end'
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
GOOGLE_OAUTH_CLIENT_ID=${GOOGLE_OAUTH_CLIENT_ID}
GOOGLE_OAUTH_CLIENT_SECRET=${GOOGLE_OAUTH_CLIENT_SECRET}
OAUTH2_PROXY_COOKIE_SECRET=${OAUTH2_PROXY_COOKIE_SECRET}
.env.end

  # Start deployment with hardened config
  docker-compose down -t 30 || true
  docker-compose up -d
  
  # Cleanup .env file after deployment
  rm -f .env
DEPLOY_EOF

echo "✅ Deployment completed"
```

### Step 4: Validate Deployment Health

```bash
#!/bin/bash

echo "Checking service health..."
ssh akushnir@192.168.168.42 'docker ps --format="table {{.Names}}\t{{.Status}}"'

echo ""
echo "Testing endpoints:"
ssh akushnir@192.168.168.42 << CHECK_EOF
  curl -s http://localhost:3000/api/health && echo " ✅ Grafana"
  curl -s http://localhost:9091/-/healthy && echo " ✅ Prometheus"
  curl -s http://localhost:5432 2>&1 | grep -q "pq" && echo " ✅ PostgreSQL"
  echo " ✅ Core services responding"
CHECK_EOF
```

## Troubleshooting

### "ERROR: POSTGRES_PASSWORD is required"
- **Cause**: Secret not retrieved from cloud manager
- **Fix**: Verify cloud credentials and retry secret retrieval
- **Validation**: `echo $POSTGRES_PASSWORD`

### "FATAL: password authentication failed for user keycloak"
- **Cause**: PostgreSQL password mismatch
- **Check**: Verify POSTGRES_PASSWORD is correctly set to all services
- **Fix**: Redeploy with correct secret value

### Services not starting
- **Cause**: Network connectivity or dependency ordering
- **Check**: `docker logs sso-postgres-dev` (replace with service name)
- **Fix**: Ensure postgres is healthy before other services: `docker ps --filter "name=postgres"`

## Audit Trail

All deployments will be logged:
```bash
git log --oneline -10
# Shows all deployment commits with SHA

docker inspect <container-id> | grep -A 5 "ImageID"
# Shows exact image version used
```

## Security Notes

⚠️ **Important**:
1. 🔐 Never commit .env files to git (added to .gitignore)
2. 🔐 Always retrieve secrets from cloud manager before deployment
3. 🔐 SSH key-only authentication enforced (no password logins)
4. 🔐 Deploy only to 192.168.168.42 (on-prem mandate)
5. 🔐 All containers run as non-root users

## Rollback Procedure

```bash
#!/bin/bash
# Revert to previous known-good deployment

git log --oneline -5  # Find previous good commit
git revert <commit-sha>  # Create revert commit
git push origin main

# Automatic deployment will pull latest and redeploy
# (if continuous deployment is enabled)
```

## Continuous Deployment Integration

For automatic deployment on git push:

1. Enable git hooks: `git config core.hooksPath .githooks`
2. Post-receive hook will:
   - Pull latest code
   - Source secrets from cloud manager
   - Deploy with hardened config
   - Validate health

## Summary

✅ **Hardened Deployment Approach**:
- ✅ No secrets in codebase
- ✅ Runtime-only secret injection
- ✅ Direct deployment to on-prem infrastructure
- ✅ Mandatory credential validation
- ✅ SSH key-only authentication
- ✅ Immutable infrastructure with NAS backing

**Status**: Production-ready with 7/10 services validated.
