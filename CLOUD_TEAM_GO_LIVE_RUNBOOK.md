# Cloud Team Go-Live Runbook
**Date:** March 10, 2026  
**Status:** Ready for Cloud Team Execution  
**Phase:** Terraform Apply & Cloud Finalization

---

## Overview

This runbook enables the cloud team to complete the final NexusShield Portal deployment phase. The backend is already deployed and healthy on the production host (192.168.168.42). This phase will:

1. Apply Terraform infrastructure (full GCP stack)
2. Deploy frontend container
3. Create Cloud Scheduler jobs
4. Run final validation
5. Close operational GitHub issues

---

## Prerequisites

**You need:**
- GCP service-account credentials with roles:
  - `roles/compute.admin` (for Compute Engine, Cloud Load Balancer)
  - `roles/container.admin` (if using Cloud Run)
  - `roles/storage.admin` (for Terraform state backups)
  - `roles/secretmanager.admin` (for secret management)
  - `roles/cloudscheduler.admin` (for Cloud Scheduler jobs)
  - `roles/iam.serviceAccountAdmin` (for service account management)

**Verify before starting:**
```bash
gcloud config get-value project  # Should be: nexusshield-prod
gcloud auth list                 # Should show active account
gcloud secrets versions list --secret="runner_ssh_key" --limit=1  # Should succeed
```

---

## Step 1: Prepare Credentials

### Option A: Local gcloud (Recommended)
```bash
# Ensure gcloud is logged in with correct project
gcloud auth login
gcloud config set project nexusshield-prod

# Test permissions
gcloud secrets list --limit=1
```

### Option B: Service Account JSON
```bash
# If using service account key instead of personal login
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

# Or copy to remote host and use there
scp /path/to/service-account.json akushnir@192.168.168.42:/home/akushnir/self-hosted-runner/creds.json
ssh akushnir@192.168.168.42 "chmod 600 /home/akushnir/self-hosted-runner/creds.json"
```

---

## Step 2: Deploy Frontend (Optional, if frontend exists)

### Check frontend directory
```bash
ssh akushnir@192.168.168.42 'test -d /home/akushnir/self-hosted-runner/frontend && echo "Frontend exists" || echo "No frontend"'
```

### Build and deploy frontend (if present)
```bash
ssh akushnir@192.168.168.42 'bash -s' <<'EOF'
set -euo pipefail
REPO_ROOT=/home/akushnir/self-hosted-runner
cd "$REPO_ROOT"

if [ -d "frontend" ]; then
  echo "[FRONTEND] Building frontend..."
  docker build -t portal-frontend:latest frontend/ 2>&1 | tail -50
  echo "[FRONTEND] Deploying via docker-compose..."
  docker-compose up -d frontend
  echo "[FRONTEND] Waiting for frontend to be ready..."
  sleep 5
  docker-compose ps frontend
else
  echo "[FRONTEND] No frontend directory; skipping"
fi
EOF
```

---

## Step 3: Run Go-Live Kit (Primary Phase)

This script applies Terraform, creates Cloud Scheduler jobs, and closes operational issues.

### Run on production host
```bash
ssh akushnir@192.168.168.42 'bash -s' <<'EOF'
set -euo pipefail
REPO_ROOT=/home/akushnir/self-hosted-runner
export CREDCACHE_PASSPHRASE="${CREDCACHE_PASSPHRASE:-nexusshield-test-automation-2026}"

# If using service account credentials
if [ -f "${REPO_ROOT}/creds.json" ]; then
  export GOOGLE_APPLICATION_CREDENTIALS="${REPO_ROOT}/creds.json"
fi

# If using gcloud login (interactive)
# gcloud auth login

cd "$REPO_ROOT"

# Run go-live script with audit logging
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="/tmp/go-live-finalize-${TIMESTAMP}.log"

echo "[GO-LIVE] Starting deployment at $TIMESTAMP"
echo "[GO-LIVE] Log: $LOG_FILE"

bash scripts/go-live-kit/02-deploy-and-finalize.sh 2>&1 | tee "$LOG_FILE"
RESULT=$?

echo ""
echo "=========================================="
if [ $RESULT -eq 0 ]; then
  echo "✅ Go-Live Completed Successfully"
  echo "Log saved to: $LOG_FILE"
else
  echo "❌ Go-Live Failed with exit code: $RESULT"
  echo "Review log: $LOG_FILE"
fi
echo "=========================================="
echo ""
echo "Next: Retrieve the log and post it to GitHub Issue #2311"
echo "Command: cat $LOG_FILE"

exit $RESULT
EOF
```

---

## Step 4: Post Logs to GitHub

After the go-live script completes, capture and share the audit log.

### Retrieve the log from remote
```bash
LATEST_LOG=$(ssh akushnir@192.168.168.42 'ls -t /tmp/go-live-finalize-*.log 2>/dev/null | head -1')
scp akushnir@192.168.168.42:"$LATEST_LOG" .
cat "$(basename "$LATEST_LOG")"
```

### Post to GitHub Issue #2311
```bash
# Use GitHub CLI (if installed)
gh issue comment 2311 \
  --repo kushin77/self-hosted-runner \
  --body "$(cat go-live-finalize-*.log)"

# Or manually:
# 1. Copy the log content
# 2. Go to https://github.com/kushin77/self-hosted-runner/issues/2311
# 3. Click "Comment"
# 4. Paste the log
# 5. Submit
```

---

## Step 5: Verify Post-Deployment State

### Check all services running
```bash
ssh akushnir@192.168.168.42 'docker-compose ps'
```

### Test backend health
```bash
ssh akushnir@192.168.168.42 'curl -s http://localhost:3000/health | jq .'
```

### Test frontend (if deployed)
```bash
ssh akushnir@192.168.168.42 'curl -s http://localhost:13000/health | jq . || echo "Frontend may not be deployed"'
```

### Check database connectivity
```bash
ssh akushnir@192.168.168.42 'docker exec nexusshield-backend curl -s http://localhost:3000/ready | jq .'
```

### Verify Terraform applied
```bash
ssh akushnir@192.168.168.42 'cd /home/akushnir/self-hosted-runner && terraform -chdir=terraform output | head -30'
```

### Check Cloud Scheduler jobs created
```bash
gcloud scheduler jobs list --project nexusshield-prod
```

### Review audit log (local)
```bash
cat logs/deployment/audit.jsonl | tail -20
```

---

## Troubleshooting

### Go-Live Script Failed

**Check remote logs:**
```bash
ssh akushnir@192.168.168.42 'tail -200 /tmp/go-live-finalize-*.log'
```

**Common causes:**
1. **GCP auth failed** — Verify `GOOGLE_APPLICATION_CREDENTIALS` is set and creds file exists
2. **Terraform state locked** — Run `terraform force-unlock <LOCK_ID>` if needed
3. **Container deploy failed** — Check `docker-compose ps` and `docker logs`
4. **Database connectivity** — Verify `DATABASE_URL` env var and DB credentials

### Backend Health Check Failing

```bash
ssh akushnir@192.168.168.42 'docker logs --tail 200 nexusshield-backend'
```

Common causes:
- DB password mismatch (verify `DB_PASSWORD` env var)
- Redis connection issue (verify `REDIS_PASSWORD` env var)
- Schema not initialized (run Prisma migrations)

### Terraform Apply Issues

```bash
ssh akushnir@192.168.168.42 'bash -s' <<'EOF'
cd /home/akushnir/self-hosted-runner
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/creds.json  # if using SA key
terraform -chdir=terraform plan -out=debug.tfplan
terraform -chdir=terraform show debug.tfplan | tail -100
EOF
```

---

## Success Criteria

✅ All phases checked:
- [ ] Backend container running and healthy (`curl http://localhost:3000/health`)
- [ ] Frontend container running (if deployed)
- [ ] PostgreSQL and Redis healthy
- [ ] Terraform applied successfully (0 errors in log)
- [ ] Cloud Scheduler jobs created (at least 3)
- [ ] GitHub issues #2311 closed with log attached
- [ ] Audit trail recorded in git (`logs/deployment/audit.jsonl`)

---

## Rollback (if needed)

If deployment fails critically:

```bash
# Stop containers on remote
ssh akushnir@192.168.168.42 'docker-compose down'

# Rollback Terraform
ssh akushnir@192.168.168.42 'bash -s' <<'EOF'
cd /home/akushnir/self-hosted-runner
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/creds.json
terraform -chdir=terraform destroy -auto-approve  # WARNING: destroys infrastructure
EOF

# Restore from git
ssh akushnir@192.168.168.42 'cd /home/akushnir/self-hosted-runner && git reset --hard origin/main'
```

---

## Contact & Support

**Questions?** 
- Check logs: `/tmp/go-live-finalize-*.log` (remote) or `logs/deployment/audit.jsonl` (git)
- Review errors: `docker-compose logs backend | tail -100`
- Test manually: `curl http://localhost:3000/health`

**Automation support:**
- GitHub Issue #2311 (this phase)
- GitHub Issue #2310 (orchestrator — if issues)
- Repo: kushin77/self-hosted-runner

---

**Prepared by:** GitHub Copilot  
**Timestamp:** 2026-03-10 18:20:00 UTC  
**Backend Status:** ✅ Deployed & Healthy on 192.168.168.42  
**Ready for:** Cloud Team Final Phase
