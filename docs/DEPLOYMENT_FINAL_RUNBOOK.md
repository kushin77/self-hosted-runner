# NexusShield Portal - Final Deployment Runbook
**Date:** March 10, 2026  
**Status:** ✅ **PRODUCTION READY**  
**Target Host:** 192.168.168.42 (fullstack production)  
**Automation:** 100% hands-off, no manual intervention required  

---

## 🎯 Executive Summary

The NexusShield Portal deployment is **100% automated**, **fully immutable**, and **completely hands-off**. 

**Key Characteristics:**
- ✅ **Immutable:** Docker images locked at build time, no runtime config changes
- ✅ **Idempotent:** All scripts safe to re-run multiple times without side effects
- ✅ **Ephemeral:** No data stored on deployment host; all data in PostgreSQL
- ✅ **Zero-Ops:** Fully automated with no manual steps required
- ✅ **Security:** GSM Vault + GCP Cloud KMS encryption for all secrets
- ✅ **Audit Trail:** Immutable JSON Lines format recording all operations
- ✅ **No GitHub Actions:** Direct bash/docker-compose deployment model
- ✅ **No Pull Requests:** Direct commits to main branch, no PR workflow

---

## 📋 Pre-Deployment Checklist

### 1. **Verify Deployment Host Accessibility**
```bash
# Test SSH connectivity to fullstack host
ssh runner@192.168.168.42 "echo 'SSH OK'; docker --version; docker-compose --version"
```
**Expected Output:**
```
SSH OK
Docker version 24.x.x
docker-compose version 2.x.x
```

### 2. **Prepare Environment Configuration**
Create `.env.production` on the deployment host or configure it before deployment:

```bash
# On deployment host or pass via deploy script
cat > /home/runner/.env.production << 'EOF'
# GCP Configuration
GCP_PROJECT_ID=your-actual-gcp-project-id
GCP_KMS_KEY=projects/your-project/locations/us-BASE64_BLOB_REDACTED
GOOGLE_APPLICATION_CREDENTIALS=/home/runner/service-account-key.json

# Database Configuration
DATABASE_URL=postgresql://nexusshield:$SECURE_REDACTED@192.168.168.42:5432/nexusshield
REDACTED=REDACTED

# Cache Configuration
REDIS_PASSWORD=$SECURE_REDIS_PASSWORD

# Application Configuration
NODE_ENV=production
PORT=3000
FRONTEND_PORT=3001

# Deployment Tracking
DEPLOYMENT_ID=$(date +%s)
DEPLOYMENT_HOST=192.168.168.42
EOF
```

**Critical:** Never commit `.env.production` to version control. It must be configured on the deployment target host.

### 3. **Place GCP Service Account Key**
```bash
# Copy your GCP service account JSON to the deployment host
scp /path/to/service-account-key.json runner@192.168.168.42:/home/runner/
ssh runner@192.168.168.42 "chmod 600 /home/runner/service-account-key.json"
```

### 4. **Run Pre-Deployment Validation**
The validation script ensures all prerequisites are met:

```bash
# Run on your local machine (where you run deployments from)
bash scripts/pre-deploy-validation.sh
```

**Validation Checks:**
1. ✅ **Correct Host:** Blocks localhost, enforces 192.168.168.42
2. ✅ **SSH Access:** Verifies connectivity to fullstack host
3. ✅ **Configuration:** Checks .env.production exists and has no placeholders
4. ✅ **Required Fields:** Confirms GCP_PROJECT_ID, KMS_KEY, etc. are real values
5. ✅ **Docker:** Tests Docker availability on target host
6. ✅ **Disk Space:** Verifies >500MB free space on target
7. ✅ **Network:** Tests connectivity to required services

---

## 🚀 Deployment Procedure

### Step 1: Run Pre-Deployment Validation
```bash
# MANDATORY FIRST STEP - This script must pass before deployment
bash scripts/pre-deploy-validation.sh
```

If any checks fail, fix the issues and re-run until all pass (green ✅).

### Step 2: Execute Deployment
```bash
# Deploy to production host (192.168.168.42)
DEPLOY_HOST=192.168.168.42 bash scripts/deploy-portal.sh
```

**Deployment Script Actions:**
1. Verifies deployment target is 192.168.168.42 (BLOCKS localhost)
2. Connects via SSH to fullstack host
3. Clones/pulls latest code from main branch
4. Copies .env.production to deployment host
5. Builds Docker images on target host
6. Starts all services (PostgreSQL, Redis, Backend, Frontend)
7. Runs health checks for all containers
8. Creates immutable audit log entry
9. Reports deployment status and URLs

**Expected Output:**
```
✅ Deployment Host: 192.168.168.42
✅ SSH Connection Established
✅ Code Repository Updated
✅ Configuration Deployed
✅ Docker Images Built
✅ Services Started
✅ Health Checks: ALL PASS

📊 Deployment Complete
- Frontend: http://192.168.168.42:3001
- Backend API: http://192.168.168.42:3000
- Metrics: http://192.168.168.42:3000/metrics
- Deployment ID: <timestamp>
```

### Step 3: Run Integration Tests
```bash
# Verify all services are operational
bash scripts/test-portal.sh
```

**Integration Tests Cover:**
- Authentication (JWT, OAuth)
- Credential management (CRUD operations)
- Audit logging (JSONL format)
- GSM Vault integration
- KMS encryption
- API health checks
- Database connectivity
- Redis cache functionality
- Frontend accessibility

**Expected Output:**
```
✅ 25/25 Tests Passed
- Authentication: PASS
- Credentials: PASS
- Audit Logging: PASS
- Health Checks: PASS
- Integration: PASS
```

---

## 📊 Post-Deployment Verification

### 1. Access the Portal
```bash
# Frontend
echo "Open in browser: http://192.168.168.42:3001"

# Backend API health
curl http://192.168.168.42:3000/health
# Expected: {"status": "ok"}

# Metrics endpoint
curl http://192.168.168.42:3000/metrics
# Expected: Prometheus format metrics
```

### 2. Check Service Status
```bash
# SSH to deployment host
ssh runner@192.168.168.42

# Check all services running
docker-compose ps
# Expected: All containers running
```

### 3. Verify Audit Trail
```bash
# Check deployment audit log
tail -f logs/deployment/audit.jsonl
# Expected: Latest deployment event recorded
```

### 4. Test Credential Operations
```bash
# Use the backend API to test credential storage
curl -X POST http://192.168.168.42:3000/credentials \
  -H "Content-Type: application/json" \
  -d '{"name": "test-cred", "type": "aws", "access_key": "...", "secret": "..."}'
  
# Expected: 201 Created with encrypted credential returned
```

---

## 🔄 Scaling & High Availability

The deployment is designed for immutable scaling:

```bash
# To scale backend replicas (via docker-compose on host)
ssh runner@192.168.168.42
docker-compose up -d --scale backend=3
```

All backend instances will:
- ✅ Connect to same PostgreSQL instance
- ✅ Share Redis cache layer
- ✅ Write to same audit log
- ✅ Share GSM/KMS credentials

---

## 🔙 Rollback Procedure

**Immutable Deployment Rollback:**

```bash
# All deployment images are tagged with deployment ID
# To rollback to previous version:

# 1. Get list of deployment IDs (stored in audit log)
ssh runner@192.168.168.42 "grep 'deployment_id' logs/deployment/audit.jsonl | tail -5"

# 2. Redeploy previous version
# (Re-run deployment script - it will use stored DEPLOYMENT_ID)
DEPLOYMENT_ID=<previous_id> DEPLOY_HOST=192.168.168.42 bash scripts/deploy-portal.sh

# 3. Verify rollback
bash scripts/test-portal.sh
```

Since deployments are fully immutable, rollback is simply redeploying a previous known-good image.

---

## 📈 Monitoring & Maintenance

### Automated Health Checks
All services include health checks that run every 10 seconds:
```bash
# Health check status
ssh runner@192.168.168.42
docker-compose ps  # Shows health status for each service
```

### Automated Credential Rotation
Credentials rotate automatically on a schedule:
```bash
# Check rotation schedule
ssh runner@192.168.168.42
systemctl status nexusshield-credential-rotation.timer
```

### Automated Backups
PostgreSQL data is backed up to persistent volume (no manual intervention needed).

---

## 🚨 Troubleshooting

### Issue: Pre-Deployment Validation Fails

**Check 1: Deployment Host**
```bash
# Must be 192.168.168.42, not localhost
echo $DEPLOY_HOST
# Expected: (empty - will default to 192.168.168.42)
```

**Check 2: SSH Access**
```bash
ssh runner@192.168.168.42 "whoami"
# If fails: Add SSH key or fix runner@192.168.168.42 credentials
```

**Check 3: Environment Configuration**
```bash
# Ensure .env.production exists on target host
ssh runner@192.168.168.42 "cat /home/runner/.env.production | grep -v PASSWORD"
# All placeholders must be replaced with real values
```

**Check 4: Docker on Target**
```bash
ssh runner@192.168.168.42 "docker version && docker-compose version"
# Both must be installed and user must have permission to run docker
```

### Issue: Deployment Fails

**Check Deployment Logs**
```bash
# SSH to host and check docker-compose logs
ssh runner@192.168.168.42
docker-compose logs --tail=50 backend
docker-compose logs --tail=50 postgres
docker-compose logs --tail=50 redis
```

**Common Issues:**
1. **Port already in use:** Another service using 3000, 3001, 5432, 6379
2. **Insufficient disk space:** Need >500MB free
3. **Database initialization timeout:** Postgres needs 30+ seconds to start
4. **Redis connection error:** Redis password mismatch in .env.production

### Issue: Tests Fail After Deployment

**Check API Connectivity**
```bash
curl -v http://192.168.168.42:3000/health
# Must return 200 OK
```

**Check Database**
```bash
# SSH to host
ssh runner@192.168.168.42
docker-compose exec postgres psql -U nexusshield -d nexusshield -c "\\dt"
# Should show tables created
```

**Check Redis**
```bash
ssh runner@192.168.168.42
docker-compose exec redis redis-cli PING
# Expected: PONG
```

---

## ✅ Sign-Off Checklist

After successful deployment, verify:

- [ ] Pre-deployment validation passes (✅ All 8 checks)
- [ ] Deployment completes without errors
- [ ] All services running (docker-compose ps shows GREEN)
- [ ] Integration tests pass (25/25)
- [ ] Frontend accessible at 192.168.168.42:3001
- [ ] Backend API responds at 192.168.168.42:3000/health
- [ ] Metrics endpoint working at 192.168.168.42:3000/metrics
- [ ] Audit log created with deployment event
- [ ] Database tables initialized
- [ ] Redis cache operational
- [ ] Credentials can be stored and encrypted
- [ ] No errors in docker-compose logs

---

## 📞 Support & Escalation

### Critical Issues
If deployment fails:
1. ✅ Review deployment script output (captures all errors)
2. ✅ Check pre-deployment validation output (identifies root cause)
3. ✅ Review docker-compose logs on target host
4. ✅ Verify .env.production configuration
5. ✅ Check SSH access and permissions

### Emergency Stop
```bash
# Stop all services immediately
ssh runner@192.168.168.42
docker-compose down
```

### Emergency Start
```bash
# Restart all services (using same immutable images)
ssh runner@192.168.168.42
cd /path/to/self-hosted-runner
docker-compose up -d
```

---

## 🎓 Summary

**The NexusShield Portal deployment is:**
- ✅ **Fully Automated:** Zero manual steps after pre-deployment validation
- ✅ **Immutable:** All configuration locked in Docker images
- ✅ **Idempotent:** Safe to re-run deployment script without side effects
- ✅ **Secure:** GSM Vault + KMS encryption for all credentials
- ✅ **Observable:** Complete audit trail in JSON Lines format
- ✅ **Resilient:** Built-in health checks and automatic recovery
- ✅ **Scalable:** Easy to scale services horizontally
- ✅ **Production-Ready:** No GitHub Actions, no PRs, direct deployment to 192.168.168.42

**Next Steps:**
1. Configure `.env.production` on deployment host
2. Run `bash scripts/pre-deploy-validation.sh`
3. Run `DEPLOY_HOST=192.168.168.42 bash scripts/deploy-portal.sh`
4. Verify with `bash scripts/test-portal.sh`

**Deployment Ready:** ✅ **GO LIVE**
