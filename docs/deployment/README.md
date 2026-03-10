# NexusShield Backend - Deployment Documentation

**Status:** ✅ Production Ready  
**Deployment Target:** 192.168.168.42 (NOT localhost)  
**Last Updated:** 2026-03-10  

---

## 📚 Documentation Index

### Quick Links

| Document | Purpose | Time | Audience |
|----------|---------|------|----------|
| [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) | Pre/during/post deployment verification | 45 min | DevOps, SRE |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Comprehensive deployment procedures | 2 hours | All engineers |
| [QUICK_REFERENCE.md](QUICK_REFERENCE.md) (if exists) | One-page deployment summary | 5 min | Experienced operators |
| [AWS_DEPLOYMENT.md](AWS_DEPLOYMENT.md) (if exists) | AWS-specific deployment steps | 1 hour | AWS users |

---

## 🚀 Deployment Paths

### Path 1: Quick Deploy (Experienced Teams)

**Time:** 15 minutes  
**Prerequisites:** SSH access to 192.168.168.42, Docker/npm installed locally  

```bash
# 1. Run validation
bash scripts/validate-deployment.sh

# 2. Run automated deploy
bash scripts/deployment/deploy-portal.sh

# 3. Verify
curl http://192.168.168.42:3000/ready
```

### Path 2: Manual Deploy (With Full Control)

**Time:** 45 minutes  
**Best for:** First-time deployments, troubleshooting  

See: [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)

### Path 3: Staged Deploy (Blue-Green)

**Time:** 1 hour  
**Best for:** Zero-downtime updates  

```bash
# 1. Deploy to blue environment
docker-compose -f docker-compose.blue.yml up -d

# 2. Verify health
curl http://192.168.168.42:3000/blue/ready

# 3. Switch traffic
curl -X POST http://192.168.168.42:9000/admin/switch-to-blue

# 4. Monitor
curl http://192.168.168.42:3000/metrics
```

---

## ✅ Pre-Deployment Validation

### Automated Validation

```bash
bash scripts/validate-deployment.sh
```

**Checks:**
- ✅ SSH connectivity to 192.168.168.42
- ✅ Docker/Docker Compose installed
- ✅ PostgreSQL 15+ available
- ✅ 500MB+ disk space
- ✅ No conflicting services on ports 3000/5432/6379
- ✅ Credentials are NOT placeholders
- ✅ Current state backed up

### Manual Verification

```bash
# Host access
ssh runner@192.168.168.42 "docker ps"

# Credentials
grep "^GCP_PROJECT_ID=" backend/.env.production
grep "^DATABASE_URL=" backend/.env.production

# Git status
git status

# Local build
cd backend && npm run build && cd ..
```

---

## 🔄 Deployment Workflow

### Phase 1: Preparation (10 min)
- [ ] Verify deployment host is 192.168.168.42
- [ ] Back up current state
- [ ] Build TypeScript
- [ ] Build Docker image

### Phase 2: Deployment (10 min)
- [ ] Stop current services
- [ ] Transfer config files
- [ ] Start new services
- [ ] Wait for health checks

### Phase 3: Validation (15 min)
- [ ] Check liveness endpoint
- [ ] Check readiness endpoint
- [ ] Verify database connection
- [ ] Test authentication
- [ ] Verify audit trail

### Phase 4: Signoff (5 min)
- [ ] Complete deployment checklist
- [ ] Notify stakeholders
- [ ] Update issue tracker
- [ ] Document any issues

---

## 🆘 Emergency Procedures

### Immediate Rollback

```bash
ssh runner@192.168.168.42 << 'EOF'
# Stop all services
docker-compose down

# Restore from backup
docker load < /tmp/nexusshield-backend-backup.tar
docker-compose up -d
EOF
```

### Database Recovery

```bash
ssh runner@192.168.168.42 << 'EOF'
# List available backups
ls -lh ~/nexusshield_db_backup*.sql.gz

# Restore from backup
gunzip < ~/nexusshield_db_backup_2026_03_10.sql.gz | \
  docker exec -i nexusshield-postgres psql \
    postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield
EOF
```

### Complete System Reset

```bash
# WARNING: This deletes all data!
ssh runner@192.168.168.42 << 'EOF'
docker-compose down -v
rm -rf ~/docker-volumes/postgres
docker-compose up -d
EOF
```

---

## 📊 Health Check Endpoints

After deployment, test these endpoints:

```bash
# Liveness (service is running)
curl http://192.168.168.42:3000/alive
# Response: {"status":"alive","timestamp":"..."}

# Readiness (service ready for requests)
curl http://192.168.168.42:3000/ready
# Response: {"status":"ready",...}

# Full diagnostics (requires auth)
TOKEN=$(curl -s -X POST http://192.168.168.42:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@test.local"}' | jq -r '.token')

curl -H "Authorization: Bearer $TOKEN" \
  http://192.168.168.42:3000/api/diagnostics/status

# Metrics
curl http://192.168.168.42:3000/metrics | head -20
```

---

## 🔐 Security Considerations

### Before Deploying

**Credentials:**
- [ ] GCP service account key is valid JSON
- [ ] KMS key exists and is accessible
- [ ] Database credentials are correct
- [ ] JWT secret is 256+ bits
- [ ] Redis password is strong
- [ ] No credentials in git history

**Network:**
- [ ] Firewall allows 192.168.168.42:3000
- [ ] Database accessible only from backend
- [ ] Redis accessible only from backend
- [ ] SSH key installed on 192.168.168.42
- [ ] No public network exposure

**Configuration:**
- [ ] CORS_ORIGINS restricts to trusted hosts
- [ ] DEPLOYMENT_ENV=production (not development)
- [ ] All TLS certificates are valid
- [ ] Audit logging enabled

---

## 📈 Post-Deployment Monitoring

### First Hour

Check every 15 minutes:
```bash
curl -s http://192.168.168.42:3000/metrics | grep -E "request_total|error_total"
```

### Daily

```bash
# Check for errors
ssh runner@192.168.168.42 "docker-compose logs backend | grep -i error | tail -20"

# Check resource usage
ssh runner@192.168.168.42 "docker stats nexusshield-backend --no-stream"

# Check database connections
ssh runner@192.168.168.42 << 'EOF'
psql postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield \
  -c "SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname;"
EOF
```

### Weekly

- [ ] Review deployment logs
- [ ] Check audit trail for anomalies
- [ ] Verify backups exist
- [ ] Monitor disk usage
- [ ] Check certificate expiry
- [ ] Review error rates

---

## 🐛 Troubleshooting

### Service Won't Start

```bash
# Check logs
ssh runner@192.168.168.42 "docker-compose logs backend"

# Common issues:
# 1. Port already in use
netstat -tuln | grep 3000

# 2. Database connection failed
docker-compose logs postgres

# 3. Out of disk space
df -h /

# 4. Permission denied
whoami
id -u
```

### High Error Rate

```bash
# Check recent errors
curl -s http://192.168.168.42:3000/api/diagnostics/errors?limit=50

# Check logs
ssh runner@192.168.168.42 "docker-compose logs -f backend | grep -i error"

# Check resource limits
ssh runner@192.162.168.42 "docker stats nexusshield-backend"
```

### Database Connection Issues

```bash
# Test database
ssh runner@192.168.168.42 << 'EOF'
docker exec nexusshield-postgres psql \
  postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield \
  -c "SELECT 1"
EOF

# Check connection pooling
curl -H "Authorization: Bearer $TOKEN" \
  http://192.168.168.42:3000/api/diagnostics/db-pool
```

---

## 📞 Support & Escalation

### For Questions
1. Check this documentation
2. Review logs: `docker-compose logs`
3. Check GitHub issues
4. Reach out to the team

### For Issues
1. Document error message
2. Run diagnostics script
3. Check health endpoints
4. Gather logs and metrics
5. File GitHub issue with details

### Emergency Contact
- On-call: (check runbook)
- GitHub Discussions: [github.com/kushin77/self-hosted-runner/discussions](https://github.com/kushin77/self-hosted-runner/discussions)

---

## ✅ Deployment Verification Checklist

After every deployment:

- [ ] SSH access to 192.168.168.42 works
- [ ] All services running: `docker-compose ps`
- [ ] No errors in first 5 minutes: `docker-compose logs`
- [ ] Health endpoints return 200: `/alive`, `/ready`
- [ ] Database connected and responsive
- [ ] Metrics being exported: `/metrics`
- [ ] Audit trail recording events
- [ ] Authentication working (can create token)
- [ ] Can list credentials (with token)
- [ ] Error rate is 0-1% (normal baseline)
- [ ] Memory usage stable (not growing)
- [ ] CPU usage < 50% (at rest)
- [ ] Disk usage < 80% (with headroom)
- [ ] No recent ERROR logs

---

## 📚 Related Documentation

- [backend/README.md](../../backend/README.md) - API reference
- [backend/DEPLOYMENT_GUIDE.md](../../backend/DEPLOYMENT_GUIDE.md) - Detailed operations manual
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Development guidelines
- [.instructions.md](../../.instructions.md) - Repository governance

---

**Last Updated:** 2026-03-10  
**Next Review:** 2026-04-10  
**Status:** ✅ Production Ready
