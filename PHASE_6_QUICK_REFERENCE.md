# Phase 6: Quick Reference Card
**Status:** READY  
**Date:** 2026-03-10  

---

## One-Line Execution
```bash
bash scripts/phase6-quickstart.sh
```

---

## Manual Step-by-Step (5 minutes each)

### 1. Build
```bash
docker-compose -f docker-compose.phase6.yml build --no-cache
```

### 2. Start
```bash
docker-compose -f docker-compose.phase6.yml up -d
```

### 3. Initialize DB
```bash
sleep 10
for f in backend/migrations/*.sql; do
  psql -U portal_user -d portal_db -f "$f"
done
```

### 4. Verify
```bash
bash scripts/phase6-integration-verify.sh
bash scripts/phase6-health-check.sh
```

### 5. Test
```bash
pytest backend/tests/integration/ -v
npm --prefix frontend run test:e2e
```

---

## Access Points

| Service | URL | User | Pass |
|---------|-----|------|------|
| Frontend | localhost:3000 | - | - |
| API | localhost:8080 | - | - |
| Grafana | localhost:3001 | admin | (see .env) |
| Prometheus | localhost:9090 | - | - |
| Jaeger | localhost:16686 | - | - |
| RabbitMQ | localhost:15672 | guest | guest |
| Adminer | localhost:8081 | portal_user | (see .env) |

---

## Health Checks

```bash
# API
curl http://localhost:8080/health

# Database
psql -U portal_user -d portal_db -c "SELECT 1"

# Redis
redis-cli -h localhost ping

# Prometheus
curl http://localhost:9090/-/ready

# All
bash scripts/phase6-health-check.sh
```

---

## Common Issues

| Issue | Fix |
|-------|-----|
| Ports in use | `docker system prune -af` |
| Build fails | `docker system prune -a` then rebuild |
| DB won't init | `docker-compose down -v` then restart |
| Tests fail | Check `.env` secrets, verify DB running |
| No metrics | Wait 30s, check Prometheus targets UI |

---

## Logs & Debugging

```bash
# Audit trail
cat logs/*.jsonl | jq '.'

# Container logs
docker logs nexusshield-api
docker logs nexusshield-database
docker logs nexusshield-frontend

# All logs
docker-compose -f docker-compose.phase6.yml logs

# Follow logs
docker-compose -f docker-compose.phase6.yml logs -f
```

---

## Stopping & Cleanup

```bash
# Stop all (keep data)
docker-compose -f docker-compose.phase6.yml stop

# Stop & remove (delete data!)
docker-compose -f docker-compose.phase6.yml down -v
```

---

## Success Indicators

✓ All 9 containers running: `docker ps | wc -l`  
✓ API responds: `curl http://localhost:8080/health`  
✓ DB has tables: `psql -U portal_user -d portal_db -c "\dt"`  
✓ Health score >95%: `bash scripts/phase6-health-check.sh`  
✓ Tests pass: `pytest -v && exit 0`  

---

**Time to Ready:** 30-45 minutes  
**Time to Verified:** 50 minutes  
**Time to Production-Ready:** 1-2 hours
