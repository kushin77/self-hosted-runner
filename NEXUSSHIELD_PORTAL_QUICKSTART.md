# NexusShield Portal - Quick Reference Guide

**For:** Operations Teams, DevOps Engineers, SRE  
**Date:** March 12, 2026  
**Status:** Ready to Use

---

## 🚀 GET STARTED IN 5 MINUTES

### 1. Start Portal (Development)

```bash
cd /home/akushnir/self-hosted-runner/portal
pnpm install           # One-time
pnpm portal:dev        # Starts both API + Frontend
```

**Result:**
- 🌐 Frontend: http://localhost:3000
- 🔌 API: http://localhost:5000
- ✅ Health: http://localhost:5000/health

### 2. Explore UI

- **Dashboard:** Real-time stats, recent activity
- **Deployments:** View all deployments across environments
- **Secrets:** Manage credentials and rotation
- **Observability:** Service health and metrics
- **Diagrams:** (Coming soon) Troubleshoot failures visually
- **Settings:** Configuration

### 3. Try API

```bash
# List products
curl http://localhost:5000/api/v1/products | jq

# Get deployments
curl http://localhost:5000/api/v1/ops/deployments | jq

# Get service status
curl http://localhost:5000/api/v1/ops/observability/status | jq
```

---

## 📋 KEY COMMANDS

```bash
# Development
pnpm portal:dev          # Start both services
pnpm -C packages/api dev # Just backend
pnpm -C packages/frontend dev # Just frontend

# Building
pnpm build               # Build all packages
pnpm build:prod          # Production build with optimizations

# Testing & Quality
pnpm test               # Run all tests
pnpm lint               # Check code style
pnpm format             # Auto-format code
pnpm type-check         # TypeScript validation

# Docker
pnpm docker:build       # Build image
pnpm docker:run         # Run container
docker-compose -f portal/docker/docker-compose.yml up # Compose

# Utilities
pnpm clean              # Remove all build artifacts
pnpm setup              # Install + Build (fresh start)
```

---

## 📂 DIRECTORY GUIDE

```
portal/                          ← Main portal directory
├── packages/                    ← Code packages
│   ├── core/                   ← Shared types & services
│   ├── api/                    ← Backend Express API
│   ├── diagram-engine/         ← Failure analysis & diagrams
│   ├── frontend/               ← React UI
│   └── products/
│       ├── ops/                ← OPS features (active)
│       └── security/           ← Security suite (future)
├── docker/                     ← Container configs
├── ci/                         ← CI/CD pipelines
├── docs/                       ← Documentation
│   ├── ARCHITECTURE.md         ← System design
│   ├── API.md                  ← API reference
│   ├── DIAGRAM_ENGINE.md       ← Troubleshooting guide
│   └── DEPLOYMENT.md           ← Production setup
└── README.md                   ← Start here
```

---

## 🔗 API ENDPOINTS CHEAT SHEET

### Health & Status
```
GET  /health                           ← Server health
GET  /api/version                      ← API version
GET  /api/v1/products                  ← Available products
```

### OPS - Deployments
```
GET  /api/v1/ops/deployments           ← List all
GET  /api/v1/ops/deployments/:id       ← Get one
POST /api/v1/ops/deployments           ← Create
```

### OPS - Secrets
```
GET  /api/v1/ops/secrets               ← List all
GET  /api/v1/ops/secrets/:id           ← Get one
POST /api/v1/ops/secrets/:id/rotate    ← Rotate
```

### OPS - Observability
```
GET  /api/v1/ops/observability/status  ← Service status
```

### Diagrams (Coming Soon)
```
POST /api/v1/diagrams/analyze-failure  ← Analyze error
GET  /api/v1/diagrams/:id              ← Get diagram
```

---

## 🎯 COMMON WORKFLOWS

### Viewing Deployment Status
1. Go to http://localhost:3000
2. Click "Deployments"
3. See all deployments with health status

### Checking Secrets
1. Click "Secrets" in sidebar
2. View all secrets with expiry dates
3. Rotation status for each secret

### Service Health
1. Click "Observability"
2. See real-time service status
3. Check uptime and latency metrics

### Analyzing Failure (Future)
1. Click "Diagrams"
2. Upload error logs
3. View failure analysis diagram
4. Follow recommendations

---

## 🐳 DOCKER QUICK START

```bash
# Build image
docker build -f portal/docker/Dockerfile -t nexusshield/portal:latest .

# Run on ports 3000 (web) and 5000 (api)
docker run -p 3000:3000 -p 5000:5000 nexusshield/portal:latest

# Or use Docker Compose
cd portal/docker
docker-compose up -d
docker-compose logs -f
docker-compose down
```

---

## 🚢 KUBERNETES DEPLOYMENT

```bash
# Quick deploy (requires kubectl)
kubectl apply -f portal/k8s/deployment.yaml

# Check status
kubectl get pods -n portal
kubectl logs -f deployment/nexusshield-portal -n portal

# Forward ports to local for testing
kubectl port-forward svc/nexusshield-portal 3000:3000 5000:5000 -n portal
```

---

## 📊 ENVIRONMENT VARIABLES

### API (.env)
```bash
NODE_ENV=production      # development|production
LOG_LEVEL=info          # debug|info|warn|error
PORT=5000
HOST=0.0.0.0

# Optional: Cloud integrations
GCP_PROJECT_ID=your-project
AWS_REGION=us-east-1
```

### Frontend (.env)
```bash
VITE_API_URL=http://localhost:5000
VITE_LOG_LEVEL=info
```

---

## 🐛 DEBUGGING TIPS

### Check API Health
```bash
curl -v http://localhost:5000/health
```

### View API Logs
```bash
# In development, logs appear in terminal
# In production, check /logs/ or docker logs
docker logs <container-id>
```

### Clear Cache & Rebuild
```bash
pnpm clean
pnpm install
pnpm build
```

### Check Port Usage
```bash
# On Mac/Linux
lsof -i :3000      # Frontend
lsof -i :5000      # API

# On Windows
netstat -ano | findstr :3000
netstat -ano | findstr :5000
```

---

## 📚 DETAILED DOCUMENTATION

For more information:

| Topic | Document |
|-------|----------|
| Complete Architecture | `portal/docs/ARCHITECTURE.md` |
| Full API Reference | `portal/docs/API.md` |
| Diagram Troubleshooting | `portal/docs/DIAGRAM_ENGINE.md` |
| Production Deployment | `portal/docs/DEPLOYMENT.md` |
| Strategic Vision | `PORTAL_SAAS_ENHANCEMENT_PLAN.md` |

---

## ✅ VERIFICATION CHECKLIST

After starting the portal:

- [ ] Frontend loads at http://localhost:3000
- [ ] API responds at http://localhost:5000/health
- [ ] Dashboard shows stats
- [ ] Can see deployments
- [ ] Can see secrets
- [ ] Can see service status
- [ ] API endpoints respond with JSON

---

## 🆘 GETTING HELP

### If Frontend Won't Start
```bash
# Check if port 3000 is in use
lsof -i :3000
# If in use, kill: kill -9 <PID>

# Rebuild frontend
pnpm -C packages/frontend build
pnpm -C packages/frontend dev
```

### If API Won't Start
```bash
# Check logs
pnpm -C packages/api dev 2>&1 | head -20

# Check port 5000
lsof -i :5000

# Rebuild API
pnpm -C packages/api build
pnpm -C packages/api start
```

### Can't Connect to API from Frontend
```bash
# Check VITE_API_URL environment variable
# Should be: http://localhost:5000

# Check CORS is enabled in API
# See: packages/api/src/app.ts
```

---

## 🔄 WORKFLOW SUMMARY

```
┌─────────────────────────────────────┐
│    User or Alert Trigger            │
└────────────┬────────────────────────┘
             │
     ┌───────▼──────────┐
     │  Portal Frontend │
     │  (React UI)      │
     └───────┬──────────┘
             │ HTTP
     ┌───────▼──────────┐
     │  Portal API      │
     │  (Express.js)    │
     └───────┬──────────┘
             │
    ┌────────┴─────────────────────┐
    │         │         │          │
    ▼         ▼         ▼          ▼
  [OPS]    [Ops]  [Diagram]  [Future
 Prod    Secrets  Engine    Products]
    │         │         │
    └────────┬─────────┘
             │
      [Show Results in UI]
```

---

## 🎓 LEARNING PATH

1. **5 min:** Try Quick Start above
2. **15 min:** Read portal/README.md
3. **30 min:** Explore portal/docs/ARCHITECTURE.md
4. **30 min:** Review portal/docs/API.md
5. **1 hour:** Read deployment guide
6. **Ongoing:** Check logs and API responses

---

## 📞 SUPPORT

- **Docs:** See files in `portal/docs/`
- **Code:** See files in `portal/packages/*/src/`
- **Issues:** GitHub Issues
- **Logs:** Terminal (dev) or container logs (production)

---

**Quick Links:**
- Frontend: http://localhost:3000
- API: http://localhost:5000
- Health: http://localhost:5000/health
- Main Repo: https://github.com/kushin77/self-hosted-runner

---

**Version:** 1.0  
**Last Updated:** March 12, 2026
