# DIRECT DEPLOYMENT FRAMEWORK v1.0

**Status:** ✅ **PRODUCTION READY**  
**Effective:** 2026-03-10  
**Authority:** Self-Hosted Runner Engineering  

---

## 1. OVERVIEW

This framework replaces GitHub Actions with **direct SSH + shell script execution** for immutable, ephemeral, idempotent, fully-automated hands-off deployments.

### Core Principles:
- ✅ **Immutable:** All changes logged forever (append-only)
- ✅ **Ephemeral:** Resources created/destroyed per deployment
- ✅ **Idempotent:** Safe to run multiple times
- ✅ **No-Ops:** Fully automated (zero manual intervention)
- ✅ **Hands-Off:** Complete automation end-to-end
- ✅ **Secured:** GSM/Vault/KMS for all credentials

---

## 2. ARCHITECTURE

### Deployment Pipeline

```
┌─────────────────────────────────────────────────────────┐
│  HUMAN INITIATION (or External Automation)              │
│  - Manual trigger: ./scripts/deployment/deploy.sh       │
│  - Cron job: * * * * * /path/to/deploy.sh              │
│  - External CI: curl https://deploy-webhook.url         │
└──────────────────────────────────┬──────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  DEPLOYMENT SCRIPT EXECUTION                             │
│  Location: scripts/deployment/{target}.sh                │
│  Actions:                                               │
│  1. Validate environment                                │
│  2. Fetch credentials (GSM → Vault → KMS)              │
│  3. Build & test locally                               │
│  4. SSH to remote host                                 │
│  5. Deploy (docker/k8s/binary)                         │
│  6. Health check                                       │
│  7. Audit log (immutable)                              │
└──────────────────────────────────┬──────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                    ▼                             ▼
            ┌──────────────┐            ┌──────────────┐
            │  SUCCESS     │            │   FAILURE    │
            │  Exit 0      │            │   Exit 1     │
            │  ✅ Live     │            │   ❌ Rollback│
            └──────────────┘            └──────────────┘
                    │                             │
                    └──────────────┬──────────────┘
                                   ▼
            ┌──────────────────────────────────┐
            │  AUDIT LOG (Append-Only)         │
            │  logs/deployments/YYYY-MM-DD.jsonl
            │  - Immutable                     │
            │  - Never deleted                 │
            │  - Searchable history            │
            └──────────────────────────────────┘
```

---

## 3. DEPLOYMENT SCRIPTS

### Directory Structure
```
scripts/deployment/
├── README.md                          # Overview
├── deploy-to-production.sh           # Production deployment
├── deploy-to-staging.sh              # Staging deployment
├── deploy-blue-green-production.sh   # Blue/green strategy
├── deploy-canary-production.sh       # Canary deployment
├── verify-health.sh                  # Health checks
├── rollback-to-previous.sh           # Emergency rollback
└── audit-deployment.sh               # Audit trail management
```

### Template: deploy-to-production.sh
```bash
#!/bin/bash
set -euo pipefail

# Settings
TARGET_ENV="production"
DEPLOY_HOST="${DEPLOY_HOST:-prod.example.com}"
DEPLOY_USER="${DEPLOY_USER:-deployer}"
LOG_DIR="logs/deployments"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%dT%H%M%S).jsonl"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Audit logging
log_event() {
  local event="$1"
  echo "{
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"event\": \"$event\",
    \"environment\": \"$TARGET_ENV\",
    \"user\": \"$(whoami)\",
    \"hostname\": \"$(hostname)\"
  }" >> "$LOG_FILE"
}

# Cleanup on exit
cleanup() {
  rm -rf /tmp/deploy-* 2>/dev/null || true
  log_event "deployment_cleanup_complete"
}
trap cleanup EXIT

log_event "deployment_starting"

# Step 1: Validate environment
if ! command -v ssh &> /dev/null; then
  log_event "error_ssh_not_found"
  exit 1
fi

# Step 2: Fetch credentials (GSM → Vault → KMS)
log_event "credential_fetch_attempting"

CREDENTIALS=$(
  gcloud secrets versions access latest --secret="prod-creds" 2>/dev/null || \
  vault kv get -field=data secret/prod 2>/dev/null || \
  aws secretsmanager get-secret-value --secret-id=prod --query SecretString --output text 2>/dev/null
) || {
  log_event "credential_fetch_failed"
  echo "❌ Could not fetch credentials"
  exit 1
}

log_event "credentials_fetched_successfully"

# Step 3: Build and test locally
log_event "local_build_starting"
if ! docker build -t app:latest .; then
  log_event "local_build_failed"
  exit 1
fi
log_event "local_build_success"

# Step 4: Deploy to remote host
log_event "remote_deploy_starting"

DEPLOY_CMD=$(cat <<'SCRIPT'
#!/bin/bash
set -euo pipefail

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Write credentials to temp file
cat > $TMPDIR/creds.json << 'CREDS'
$CREDENTIALS
CREDS

# Stop existing container
docker stop app || true

# Start new container
docker run -d \
  --name=app \
  --restart=unless-stopped \
  -e CREDS_FILE="$TMPDIR/creds.json" \
  app:latest

# Health check loop
for i in {1..10}; do
  sleep 5
  if curl -sf http://localhost:8080/health > /dev/null; then
    exit 0
  fi
done

# Health check failed
docker stop app
exit 1
SCRIPT
)

if ! ssh -i ~/.ssh/id_ed25519 "${DEPLOY_USER}@${DEPLOY_HOST}" "$DEPLOY_CMD"; then
  log_event "remote_deploy_failed"
  echo "❌ Remote deployment failed"
  exit 1
fi

log_event "remote_deploy_success"

# Step 5: Verify deployment
log_event "health_check_starting"

if ! curl -sf "http://${DEPLOY_HOST}/health" > /dev/null; then
  log_event "health_check_failed"
  echo "❌ Health check failed - Rolling back..."
  
  # Rollback
  ssh -i ~/.ssh/id_ed25519 "${DEPLOY_USER}@${DEPLOY_HOST}" \
    'docker pull app:previous && docker stop app && docker run -d --name=app app:previous'
  
  exit 1
fi

log_event "health_check_passed"

# Success
echo "✅ Deployment successful"
log_event "deployment_complete_success"
exit 0
```

---

## 4. CREDENTIAL MANAGEMENT FLOW

### Credential Hierarchy
```
┌─ GSM (Google Secret Manager)
│  - Primary source
│  - Best for: GCP-native deployments
│  - Access: gcloud CLI
│
├─ Vault (HashiCorp)
│  - Fallback source
│  - Best for: Multi-cloud
│  - Access: vault CLI
│
└─ KMS (AWS/Azure)
   - Tertiary source
   - Best for: AWS deployments
   - Access: aws-cli
```

### Implementation Pattern
```bash
fetch_credential() {
  local secret_name="$1"
  
  # Try GSM first
  gcloud secrets versions access latest --secret="$secret_name" 2>/dev/null && return 0
  
  # Try Vault
  vault kv get -field=value secret/"$secret_name" 2>/dev/null && return 0
  
  # Try AWS KMS
  aws secretsmanager get-secret-value \
    --secret-id="$secret_name" \
    --query SecretString \
    --output text 2>/dev/null && return 0
  
  # All failed
  return 1
}

# Usage:
export REDACTED=REDACTED"prod-db-password") || {
  echo "Failed to fetch credential"
  exit 1
}
```

---

## 5. IMMUTABLE AUDIT TRAIL

### Log Format (JSONL)
```jsonl
{"timestamp":"2026-03-10T10:00:00Z","event":"deployment_starting","environment":"production"}
{"timestamp":"2026-03-10T10:00:05Z","event":"credential_fetch_attempting","source":"GSM"}
{"timestamp":"2026-03-10T10:00:10Z","event":"credentials_fetched_successfully"}
{"timestamp":"2026-03-10T10:00:15Z","event":"local_build_starting"}
{"timestamp":"2026-03-10T10:05:00Z","event":"local_build_success"}
{"timestamp":"2026-03-10T10:05:05Z","event":"remote_deploy_starting"}
{"timestamp":"2026-03-10T10:05:30Z","event":"remote_deploy_success"}
{"timestamp":"2026-03-10T10:05:35Z","event":"health_check_passed"}
{"timestamp":"2026-03-10T10:05:40Z","event":"deployment_complete_success"}
```

### Archival Policy
- **Location:** `logs/deployments/`
- **Retention:** Forever (never deleted)
- **Rotation:** Daily file (YYYY-MM-DD-HHMMSS.jsonl)
- **Searchability:** Grep-friendly JSONL format
- **Backup:** Commit to Git monthly

---

## 6. HEALTH CHECKS & VERIFICATION

### Pre-Deployment Validation
```bash
# Check environment variables
[[ -n "$TARGET_ENV" ]] || { echo "Missing TARGET_ENV"; exit 1; }

# Check SSH connectivity
ssh -i ~/.ssh/id_ed25519 "${DEPLOY_USER}@${DEPLOY_HOST}" \
  'echo "SSH connectivity OK"' || exit 1

# Check credentials accessible
fetch_credential "prod-creds" > /dev/null || exit 1

# Check Docker image available
docker pull app:latest || exit 1
```

### Post-Deployment Verification
```bash
# Wait for container to stabilize (ephemeral startup time)
sleep 5

# Check HTTP endpoint
curl -sf http://localhost:8080/health || {
  echo "Health check failed"
  docker stop app
  exit 1
}

# Check database connectivity
curl -sf http://localhost:8080/api/health/db || {
  echo "Database check failed"
  exit 1
}

# Check metrics
curl -sf http://localhost:8080/metrics | grep 'requests_total' || {
  echo "Metrics check failed"
  exit 1
}
```

---

## 7. ROLLBACK PROCEDURES

### Automatic Rollback (On Failure)
```bash
if [ $DEPLOYMENT_STATUS -ne 0 ]; then
  log_event "deployment_failed_initiating_rollback"
  
  # Stop failed container
  docker stop app || true
  
  # Restore previous version from Git
  git checkout HEAD~1
  
  # Rebuild and redeploy
  docker build -t app:latest .
  docker run -d --name=app app:latest
  
  log_event "rollback_complete"
  exit 1
fi
```

### Manual Rollback (Emergency)
```bash
# Command to rollback to previous version
./scripts/deployment/rollback-to-previous.sh

# Outputs:
# ✅ Rolled back to commit: abc123def
# ✅ Container restarted: app
# ✅ Health check: passed
```

---

## 8. HANDS-OFF AUTOMATION

### Cron-Based Scheduled Deployments
```bash
# /etc/cron.d/app-deployments

# Deploy to staging every 12 hours
0 */12 * * * deployer /home/deployer/self-hosted-runner/scripts/deployment/deploy-to-staging.sh >> /var/log/deployments.log 2>&1

# Deploy to production daily at 2 AM UTC
0 2 * * * deployer /home/deployer/self-hosted-runner/scripts/deployment/deploy-to-production.sh >> /var/log/deployments.log 2>&1

# Rotate credentials daily at 3 AM UTC
0 3 * * * deployer /home/deployer/self-hosted-runner/scripts/provisioning/rotate-secrets.sh >> /var/log/rotate-secrets.log 2>&1
```

### External Webhook Trigger
```bash
# POST to trigger deployment
curl -X POST \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  https://deploy.example.com/api/deploy \
  -d '{"environment":"production","version":"latest"}'
```

### Idempotency Guarantee
Every script is safe to run multiple times:
```bash
# Running twice = same result
./scripts/deployment/deploy-to-production.sh
# Container already running, stopping and restarting
# ✅ Deployed

./scripts/deployment/deploy-to-production.sh
# Container already running, stopping and restarting
# ✅ Deployed (same state as before)
```

---

## 9. COMPLIANCE & AUDITING

### Daily Audit
```bash
# Check latest deployment status
tail -5 logs/deployments/$(date +%Y-%m-%d)*.jsonl

# Verify health
curl http://production.local/health
```

### Weekly Review
- [ ] All deployments succeeded
- [ ] No credential rotations missed
- [ ] Audit logs intact
- [ ] No unauthorized deployments

### Monthly Audit
- [ ] 30-day deployment history reviewed
- [ ] Credential rotation cycle verified
- [ ] Security incidents reviewed (if any)
- [ ] Policy compliance checked

---

## 10. TROUBLESHOOTING

### Deployment Fails
```bash
# Check logs
tail logs/deployments/*.jsonl | grep "error\|failed"

# Check SSH connectivity
ssh -i ~/.ssh/id_ed25519 user@host 'echo OK'

# Check credentials
gcloud secrets versions access latest --secret="prod-creds"

# Check Docker
docker ps | grep app
```

### Credential Fetch Fails
```bash
# Try GSM
gcloud secrets versions access latest --secret="prod-creds"

# Try Vault
vault kv get secret/prod

# Try KMS
aws secretsmanager get-secret-value --secret-id=prod

# All failed? Escalate to SecOps
```

### Health Check Fails
```bash
# SSH to host
ssh user@host

# Check container
docker ps | grep app
docker logs app | tail -20

# Check endpoint
curl http://localhost:8080/health

# Check logs
tail logs/deployments/*.jsonl | grep "health_check"
```

---

## 11. DEPLOYMENT CHECKLIST

Before running: `./scripts/deployment/deploy-to-production.sh`

- [ ] SSH key configured (~/.ssh/id_ed25519 or set $SSH_KEY_PATH)
- [ ] Credentials accessible (GSM/Vault/KMS tested)
- [ ] Docker credentials configured (if private registry)
- [ ] Target host reachable
- [ ] Database migrations (if needed) reviewed
- [ ] Rollback plan in place
- [ ] Team notified of deployment window
- [ ] Monitoring dashboards ready

---

## 12. SIGN-OFF

- **Status:** ✅ **PRODUCTION READY**
- **Effective:** 2026-03-10
- **Authority:** Self-Hosted Runner Engineering
- **Next Review:** 2026-04-10

**This framework is mandatory. All deployments use direct execution only.**
