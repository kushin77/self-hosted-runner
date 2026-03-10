# NexusShield Portal - Deployment Pre-Flight Checklist

**Deployment Target:** 192.168.168.42 (Production Fullstack)  
**Component:** Backend Portal  
**Status:** Production Ready  
**Last Updated:** 2026-03-10

---

## 🚨 MANDATORY: Host Verification

**BEFORE touching anything, verify the deployment host:**

```bash
# Correct host
echo "Deploying to: 192.168.168.42"

# Test SSH access
ssh -o ConnectTimeout=5 runner@192.168.168.42 "uname -a"
# Should succeed immediately

# Wrong hosts (STOP if you see these)
# localhost ❌
# 127.0.0.1 ❌
# your-computer-name ❌
# any other IP ❌
```

---

## ✅ Pre-Deployment Phase (30 minutes)

### 1. Environment Verification

- [ ] SSH to 192.168.168.42 works without errors
- [ ] Disk space > 500MB: `ssh runner@192.168.168.42 "df -h /"`
- [ ] Docker running: `ssh runner@192.168.168.42 "docker ps"`
- [ ] Docker Compose installed: `ssh runner@192.168.168.42 "docker-compose version"`
- [ ] PostgreSQL accessible: `ssh runner@192.168.168.42 "psql --version"`
- [ ] NPM/Node available: `ssh runner@192.168.168.42 "node --version && npm --version"`

### 2. Credential Verification

**CRITICAL: Verify ALL credentials are real (not placeholders)**

```bash
# Check .env.production has real values
grep -E "^(GCP_PROJECT_ID|GCP_KMS_KEY|DATABASE_URL|REDIS_PASSWORD)" \
  backend/.env.production

# Expected output:
# GCP_PROJECT_ID=nexusshield-prod
# GCP_KMS_KEY=projects/nexusshield-prod/locations/...
# DATABASE_URL=postgresql://user:pass@192.168.168.42:5432/nexusshield
# REDIS_PASSWORD=strong_password_here

# FORBIDDEN outputs (STOP if you see):
# GCP_PROJECT_ID=your_project_here
# GCP_KMS_KEY=your_key_here
# DATABASE_URL=change_me
# REDIS_PASSWORD=your_password_here
```

### 3. Backup Verification

- [ ] Current backend Docker image backed up (if exists)
- [ ] Current database backed up: `ssh runner@192.168.168.42 "pg_dump nexusshield | gzip > /tmp/nexusshield_backup_$(date +%Y%m%d_%H%M%S).sql.gz"`
- [ ] Current .env backed up: `cp backend/.env.production backend/.env.production.backup.$(date +%Y%m%d_%H%M%S)`
- [ ] Git repository clean: `git status` (no uncommitted changes)

### 4. Health Check Current State

```bash
# Test current backend health (if deployed)
curl -I http://192.168.168.42:3000/alive 2>/dev/null || echo "No backend running yet"

# If running, note these for comparison after deployment:
curl -s http://192.168.168.42:3000/ready | jq . > /tmp/health_before.json
curl -s http://192.168.168.42:3000/metrics | head -20 > /tmp/metrics_before.txt
```

---

## 🔨 Deployment Phase (15 minutes)

### Step 1: Build Local Artifacts

```bash
cd backend

# 1a. Clean previous builds
rm -rf dist/ node_modules/.cache

# 1b. Install dependencies
npm install

# 1c. Build TypeScript
npm run build
if [ $? -ne 0 ]; then
  echo "❌ TypeScript build failed. Fix errors above."
  exit 1
fi

# 1d. Verify build artifacts
[ -f dist/index.js ] && echo "✅ Build artifacts ready" || exit 1
```

### Step 2: Build Docker Image

```bash
# 2a. Build from Dockerfile
docker build \
  -t nexusshield-backend:latest \
  -t nexusshield-backend:$(date +%Y%m%d) \
  .

if [ $? -ne 0 ]; then
  echo "❌ Docker build failed. Check Dockerfile."
  exit 1
fi

# 2b. Verify image
docker images | grep nexusshield-backend
```

### Step 3: Deploy to Production

```bash
# 3a. Transfer docker-compose.yml to target
scp docker-compose.yml runner@192.168.168.42:~/docker-compose.yml

# 3b. Transfer .env.production to target
scp backend/.env.production runner@192.168.168.42:~/.env

# 3c. Save current container (backup)
ssh runner@192.168.168.42 << 'EOF'
  docker commit nexusshield-backend \
    nexusshield-backend:backup-$(date +%Y%m%d_%H%M%S) || true
  docker stop nexusshield-backend || true
  docker rm nexusshield-backend || true
EOF

# 3d. Start new deployment
ssh runner@192.168.168.42 << 'EOF'
  cd ~
  docker-compose up -d
  
  # Wait for services to stabilize
  sleep 10
  
  # Show status
  docker-compose ps
EOF
```

### Step 4: Verify Deployment

```bash
# 4a. Check services running
ssh runner@192.168.168.42 "docker-compose ps"
# All services should show "Up"

# 4b. Check logs for errors
ssh runner@192.168.168.42 "docker-compose logs backend | head -50"
```

---

## ✅ Post-Deployment Validation (20 minutes)

### Phase 1: Health Checks

```bash
# 1a. Liveness check (is service running?)
curl -i http://192.168.168.42:3000/alive
# Expected: 200 OK, {"status":"alive","timestamp":"..."}

# 1b. Readiness check (is service ready?)
curl -s http://192.168.168.42:3000/ready | jq .
# Expected: {"status":"ready","environment":"production","database":true,"cache":true}

# 1c. System diagnostics
curl -s -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://192.168.168.42:3000/api/diagnostics/status | jq .
# Expected: Shows uptime, memory, database connection pool, cache status
```

### Phase 2: Database Verification

```bash
# 2a. Connect to database
ssh runner@192.168.168.42 << 'EOF'
  psql postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield << 'SQL'
    SELECT version();
    \dt -- Show tables
    SELECT COUNT(*) as records FROM "Audit";
    SELECT COUNT(*) as records FROM "AccessLog";
SQL
EOF

# Expected: Tables exist, no errors
```

### Phase 3: Authentication Test

```bash
# 3a. Create JWT token
TOKEN=$(curl -s -X POST http://192.168.168.42:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@nexusshield.local","provider":"local"}' \
  | jq -r '.token')

echo "Token: ${TOKEN:0:20}..."

# 3b. Verify token works
curl -s -H "Authorization: Bearer $TOKEN" \
  http://192.168.168.42:3000/auth/verify | jq .
# Expected: {"valid":true,"email":"...","expiresIn":"..."}

# 3c. Test credential endpoints
curl -s -H "Authorization: Bearer $TOKEN" \
  http://192.168.168.42:3000/api/credentials | jq '.[]' | head -5
```

### Phase 4: Metrics Verification

```bash
# 4a. Prometheus metrics available
curl -s http://192.168.168.42:3000/metrics | head -20
# Should show metric exports in Prometheus format

# 4b. Compare with pre-deployment baseline
curl -s http://192.168.168.42:3000/metrics > /tmp/metrics_after.txt
diff -u /tmp/metrics_before.txt /tmp/metrics_after.txt | head -20
```

### Phase 5: Audit Trail Check

```bash
# 5a. Check audit logs
ssh runner@192.168.168.42 "docker exec nexusshield-backend tail -20 /app/logs/audit.jsonl | jq '.timestamp, .event, .user'"

# 5b. Verify immutability (append-only)
ssh runner@192.168.168.42 "docker exec nexusshield-backend wc -l /app/logs/audit.jsonl"
# Should be current or higher than before deployment
```

---

## 📊 Validation Summary

**After all checks pass, complete this verification:**

```bash
# Generate comprehensive verification report
cat << 'EOF' > /tmp/deployment_verification.sh
#!/bin/bash

echo "=== NEXUSSHIELD BACKEND DEPLOYMENT VERIFICATION ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

echo "1. Host Configuration:"
echo "   Deployment Host: 192.168.168.42"
echo "   SSH Access: $(ssh -o ConnectTimeout=2 runner@192.168.168.42 'echo OK' 2>&1)"

echo
echo "2. Service Status:"
ssh runner@192.168.168.42 "docker-compose ps" 2>/dev/null

echo
echo "3. API Endpoints:"
echo "   Alive: $(curl -s -I http://192.168.168.42:3000/alive | head -1)"
echo "   Ready: $(curl -s -I http://192.168.168.42:3000/ready | head -1)"
echo "   Metrics: $(curl -s -I http://192.168.168.42:3000/metrics | head -1)"

echo
echo "4. Database:"
echo "   URL: postgresql://...@192.168.168.42:5432/nexusshield"
DBCHECK=$(ssh runner@192.168.168.42 "psql postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield -c 'SELECT 1' 2>&1")
echo "   Status: $(echo $DBCHECK | grep -q '1 row' && echo 'Connected ✅' || echo 'Error ❌')"

echo
echo "5. Audit Trail:"
AUDITLINES=$(ssh runner@192.168.168.42 "docker exec nexusshield-backend wc -l /app/logs/audit.jsonl 2>/dev/null" | awk '{print $1}')
echo "   Audit Records: $AUDITLINES"

echo
echo "=== DEPLOYMENT VERIFICATION COMPLETE ==="
EOF

bash /tmp/deployment_verification.sh
```

---

## 🔄 Rollback Procedure (If Needed)

**Use ONLY if deployment validation fails:**

```bash
# Step 1: Stop new deployment
ssh runner@192.168.168.42 << 'EOF'
  docker-compose down
  docker stop nexusshield-backend || true
EOF

# Step 2: Restore backup
ssh runner@192.168.168.42 << 'EOF'
  # Find latest backup
  BACKUP=$(docker images | grep "nexusshield-backend:backup-" | awk '{print $2}' | sort -r | head -1)
  
  if [ -n "$BACKUP" ]; then
    echo "Restoring from backup: $BACKUP"
    docker tag nexusshield-backend:$BACKUP nexusshield-backend:latest
    docker-compose up -d
  else
    echo "ERROR: No backup found!"
    exit 1
  fi
EOF

# Step 3: Verify rollback
curl http://192.168.168.42:3000/alive
```

---

## 🚨 Emergency Shutdown

**If critical issue detected:**

```bash
# Immediate stop (no graceful shutdown)
ssh runner@192.168.168.42 << 'EOF'
  docker-compose stop
  docker stop nexusshield-backend nexusshield-postgres nexusshield-redis
  
  # Check what's running
  docker ps
EOF

# After fixing issue, restart
ssh runner@192.168.168.42 "docker-compose up -d"
```

---

## ✅ Sign-Off Checklist

After deployment and validation, complete:

- [ ] All 5 validation phases passed
- [ ] Health checks returning 200 OK
- [ ] Database connected and responding
- [ ] Authentication working (JWT token created)
- [ ] Metrics being exported
- [ ] Audit trail recording entries
- [ ] No errors in docker logs
- [ ] SSH access to 192.168.168.42 verified
- [ ] Pre-deployment backups exist
- [ ] Deployment time recorded
- [ ] Team notified of successful deployment

---

## 📋 Deployment Log

**Deployment Date:** ________  
**Deployed By:** ________  
**Version:** ________  
**Status:** ✅ SUCCESS / ❌ FAILED / ⏸️ ROLLED BACK  

**Issues Encountered:** 
```
(none, or describe here)
```

**Verification Results:**
```
(paste output of verification script above)
```

**Next Steps:**
- [ ] Update status in GitHub issues
- [ ] Notify stakeholders
- [ ] Schedule post-deployment monitoring

---

**For questions, see:** [docs/deployment/DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md)  
**For troubleshooting:** [docs/runbooks/TROUBLESHOOTING.md](../runbooks/TROUBLESHOOTING.md)
