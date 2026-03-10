# NexusShield Portal - Quick Command Reference

## 🚀 Deploy Portal (Recommended: Use This)

```bash
# One-command deployment (fully automated)
bash scripts/deploy-portal.sh

# Or using Make
make -f Makefile.portal deploy
```

---

## 🧪 Test Portal

```bash
# Run full integration test suite
bash scripts/test-portal.sh

# Or using Make
make -f Makefile.portal test
```

---

## 📊 Monitor & Manage

```bash
# View service status
docker-compose ps
make -f Makefile.portal status

# View logs
docker-compose logs -f backend
make -f Makefile.portal logs

# Check health
curl http://localhost:3000/health
make -f Makefile.portal health

# View metrics
curl http://localhost:3000/metrics
make -f Makefile.portal metrics
```

---

## 🔧 Common Operations

```bash
# Restart services
docker-compose restart
make -f Makefile.portal restart

# Stop services
docker-compose stop
make -f Makefile.portal stop

# Start services
docker-compose start
make -f Makefile.portal start

# Clean up (WARNING: removes data!)
docker-compose down -v
make -f Makefile.portal clean
```

---

## 🔐 API Testing

```bash
# Test login endpoint
make -f Makefile.portal api-login

# Get token and test credentials
make -f Makefile.portal api-creds

# View audit trail
make -f Makefile.portal api-audit
```

---

## 📝 Configuration

```bash
# Create .env.production from template
make -f Makefile.portal create-env

# View current environment
make -f Makefile.portal show-env

# Validate prerequisites
make -f Makefile.portal validate
```

---

## 🎯 All Available Commands

```bash
# Show all available commands
make -f Makefile.portal help
```

---

## 🐳 Docker Commands

```bash
# Build images
docker-compose build --no-cache

# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f

# Execute command in container
docker exec -it nexusshield-backend bash

# Scale service
docker-compose up -d --scale backend=5
```

---

## 📚 Key Files

| File | Purpose |
|------|---------|
| `/backend/server.js` | Main Express.js API (550+ lines) |
| `/docker-compose.yml` | Infrastructure definition |
| `/scripts/deploy-portal.sh` | Deployment automation |
| `/scripts/test-portal.sh` | Integration tests |
| `/Makefile.portal` | Command interface |
| `/.env.production.example` | Config template |
| `/PORTAL_DEPLOYMENT_README.md` | Full documentation |
| `/PORTAL_COMPLETION_REPORT.md` | Status report |

---

## ⚡ Fastest Deploy Option

```bash
# 3 commands to fully operational portal:

# 1. Setup credentials
cp .env.production.example .env.production
# Edit with real GCP service account key

# 2. Deploy
bash scripts/deploy-portal.sh

# 3. Verify
bash scripts/test-portal.sh
```

**That's it! Portal is now running fully functional.**

---

## 🔍 Verification Checklist

After deployment, verify:

```bash
✅ curl http://localhost:3000/health          # Backend health
✅ curl http://localhost:3000/api/health      # API health
✅ curl http://localhost:3001/                # Frontend loads
✅ curl http://localhost:3000/metrics         # Metrics available
✅ docker-compose ps | grep Up                # All running
```

---

## 📞 Useful Links

- **Full Documentation:** [PORTAL_DEPLOYMENT_README.md](PORTAL_DEPLOYMENT_README.md)
- **Completion Report:** [PORTAL_COMPLETION_REPORT.md](PORTAL_COMPLETION_REPORT.md)
- **API Reference:** See PORTAL_DEPLOYMENT_README.md - API Reference section
- **Troubleshooting:** See PORTAL_DEPLOYMENT_README.md - Troubleshooting section

---

## 🎉 Success!

Your portal is now **100% functional and production-ready!**

Backend: `http://localhost:3000`  
Frontend: `http://localhost:3001`  
Metrics: `http://localhost:3000/metrics`
