# NexusShield Dashboard - CI-Less Deployment Guide

**Status:** ✅ Complete & Operational  
**Date:** 2026-03-10T14:00:00Z  
**Framework:** Direct-Deploy (Immutable | Ephemeral | Idempotent | No-Ops)

---

## Overview

The NexusShield Dashboard is a React-based frontend that visualizes migration progress, authentication flows, and system metrics. This guide covers **zero-dependency CI deployment** - no GitHub Actions, Jenkins, or container registries required.

**Key Constraints:**
- ✅ **Immutable:** All deployments logged to append-only audit trail
- ✅ **Ephemeral:** Old containers removed before starting new ones
- ✅ **Idempotent:** Safe to run repeatedly without side effects
- ✅ **No-Ops:** Fully automated, single command deployment
- ✅ **Hands-Off:** Deployable to remote hosts via SSH

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Developer Laptop / CI Server                                │
│                                                               │
│  $ bash scripts/deploy/deploy_dashboard.sh                  │
│                                                               │
│  ├─ Build: docker build frontend/dashboard/                │
│  ├─ Push: (optional) docker tag/push to registry            │
│  └─ Deploy: SSH to remote → docker run                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ SSH (ED25519 key auth)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Production Host (Linux)                                      │
│                                                               │
│  docker run -d -p 3000:3000 nexusshield-dashboard:latest   │
│                                                               │
│  ├─ Port 3000: Dashboard endpoint                           │
│  ├─ Health: curl http://localhost:3000/health              │
│  └─ Logs: docker logs nexusshield-dashboard-prod           │
└─────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

**Local (build machine):**
- Docker (20.10+)
- Docker BuildKit enabled
- Node.js 18+ (for local development only)
- SSH client (for remote deployment)

**Remote (production host):**
- Docker (20.10+) with daemon running
- SSH server with key-based auth (ED25519)
- Port 3000 exposed (or configured via `iptables`/firewall)
- ~500MB free disk space

---

## Quick Start

### 1. One-Command Deployment (Local)

```bash
# Deploy to localhost
bash scripts/deploy/deploy_dashboard.sh localhost http://api-backend:8080

# Deploy to remote host
bash scripts/deploy/deploy_dashboard.sh app.example.com http://api-backend:8080 3000
```

### 2. Verify Deployment

```bash
# Check container status
docker ps | grep nexusshield-dashboard

# View logs
docker logs -f nexusshield-dashboard-prod

# Test health
curl http://localhost:3000/health
```

### 3. Access Dashboard

Open browser to: **http://localhost:3000**

---

## Deployment Script Reference

**File:** `scripts/deploy/deploy_dashboard.sh`

**Usage:**
```bash
./scripts/deploy/deploy_dashboard.sh [REMOTE_HOST] [API_URL] [PORT]
```

**Parameters:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `REMOTE_HOST` | `localhost` | Target host (IP or hostname, SSH accessible) |
| `API_URL` | `http://localhost:8080` | Backend API endpoint |
| `PORT` | `3000` | Frontend port (host) |

**Examples:**

```bash
# Local development
bash scripts/deploy/deploy_dashboard.sh

# Staging environment
bash scripts/deploy/deploy_dashboard.sh staging.internal.com http://api-staging:8080 3000

# Production
bash scripts/deploy/deploy_dashboard.sh prod.example.com https://api.example.com 3000
```

---

## Deployment Workflow (Detailed)

### Phase 1: Build
```bash
docker build -f frontend/dashboard/Dockerfile -t nexusshield-dashboard:latest frontend/dashboard/
```

**What happens:**
1. Multi-stage build reduces image size
2. Dependencies locked via `package-lock.json`
3. React app compiled with optimizations
4. Final image ~450MB

### Phase 2: Cleanup (Ephemeral)
```bash
docker rm -f nexusshield-dashboard-prod 2>/dev/null || true
```

**Why:** Ensures no dangling containers from previous deployments

### Phase 3: Run
```bash
docker run -d \
  --name nexusshield-dashboard-prod \
  --restart=unless-stopped \
  -p 3000:3000 \
  -e REACT_APP_API_URL='http://api-backend:8080' \
  --health-cmd='curl -f http://localhost:3000/ || exit 1' \
  --health-interval=30s \
  --health-timeout=3s \
  --health-start-period=10s \
  --health-retries=3 \
  nexusshield-dashboard:latest
```

**Configuration:**
- **Auto-restart:** `unless-stopped` (survives daemon restarts)
- **Port mapping:** `3000:3000` (expose on host)
- **Environment:** `REACT_APP_API_URL` (passed to React app)
- **Health checks:** Verify container every 30 seconds

### Phase 4: Health Verification
```bash
for i in {1..30}; do
  docker inspect --format='{{.State.Health.Status}}' nexusshield-dashboard-prod
  # Waits for "healthy" status (max 30 seconds)
done
```

### Phase 5: Systemd Integration (Optional)
```bash
sudo tee /etc/systemd/system/nexusshield-dashboard.service
sudo systemctl daemon-reload
sudo systemctl enable nexusshield-dashboard.service
```

**Why:** Auto-restart dashboard if server reboots

---

## Environment Variables

### React Application

Set these in Docker container:

| Variable | Default | Purpose |
|----------|---------|---------|
| `REACT_APP_API_URL` | `http://localhost:8080` | Backend API endpoint |
| `REACT_APP_LOG_LEVEL` | `info` | Console logging (`debug`, `info`, `warn`, `error`) |
| `REACT_APP_SESSION_TIMEOUT` | `900000` | Session timeout (ms, default 15 min) |
| `REACT_APP_REFRESH_INTERVAL` | `5000` | Data refresh rate (ms) |

### Server

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `3000` | Server port |
| `NODE_ENV` | `production` | Environment |

**Example:**
```bash
docker run -d \
  -e REACT_APP_API_URL='https://api.example.com' \
  -e REACT_APP_LOG_LEVEL='debug' \
  nexusshield-dashboard:latest
```

---

## Health Checks

### Built-in Checks

```bash
# Docker health status
docker inspect --format='{{.State.Health.Status}}' nexusshield-dashboard-prod

# HTTP health endpoint
curl -v http://localhost:3000/health
# Response: {"status": "healthy"}

# React app endpoint
curl -v http://localhost:3000/
# Response: HTML page
```

### Manual Diagnostics

```bash
# View logs
docker logs nexusshield-dashboard-prod

# Check resource usage
docker stats nexusshield-dashboard-prod

# Inspect container
docker inspect nexusshield-dashboard-prod

# Test API connectivity
docker exec nexusshield-dashboard-prod curl http://api-backend:8080/health
```

---

## Configuration Files

### Dockerfile

**Location:** `frontend/dashboard/Dockerfile`

Multi-stage build:
- **Stage 1:** Node.js build environment (compiles React)
- **Stage 2:** Minimal runtime (only necessary files)

Key optimizations:
- Alpine Linux base (small footprint)
- Health checks configured
- Production dependencies only
- Non-root user (security)

### package.json

**Location:** `frontend/dashboard/package.json`

Scripts:
```json
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "lint": "eslint src",
    "test": "vitest"
  }
}
```

---

## Logs & Audit Trail

### Container Logs

```bash
# Real-time logs
docker logs -f nexusshield-dashboard-prod

# Last 100 lines
docker logs --tail 100 nexusshield-dashboard-prod

# With timestamps
docker logs -t nexusshield-dashboard-prod

# Save to file
docker logs nexusshield-dashboard-prod > /var/log/dashboard-$(date +%Y%m%d).log
```

### Application Logs

**Inside container:** `/app/logs/`

**Host access:**
```bash
docker exec nexusshield-dashboard-prod cat /app/logs/app.log
```

### Immutable Audit Trail

**Location:** `.deployment_logs/`

Auto-created deployment records:
```
.deployment_logs/
├── 2026-03-10T14:00:00Z_dashboard_deploy.json
├── 2026-03-10T14:15:00Z_dashboard_deploy.json
└── 2026-03-10T14:30:00Z_dashboard_deploy.json
```

Format (JSONL - append-only):
```json
{
  "timestamp": "2026-03-10T14:00:00Z",
  "action": "dashboard.deploy",
  "host": "prod.example.com",
  "image": "nexusshield-dashboard:latest",
  "port": 3000,
  "api_url": "https://api.example.com",
  "health_status": "healthy",
  "container_id": "abc123def456"
}
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker logs nexusshield-dashboard-prod

# Inspect image
docker image inspect nexusshield-dashboard:latest

# Try running with verbose output
docker run -it nexusshield-dashboard:latest node server.js
```

### Port Already in Use

```bash
# Find what's using port 3000
sudo lsof -i :3000

# Kill existing process
sudo kill -9 <PID>

# Or use different port
bash scripts/deploy/deploy_dashboard.sh localhost http://api-backend:8080 3001
```

### API Connectivity Issues

```bash
# Test from inside container
docker exec nexusshield-dashboard-prod curl http://api-backend:8080/health

# Check network
docker inspect nexusshield-dashboard-prod | jq '.NetworkSettings'

# Test DNS
docker exec nexusshield-dashboard-prod nslookup api-backend
```

### Health Check Failing

```bash
# Check health details
docker inspect --format='{{json .State.Health}}' nexusshield-dashboard-prod | jq

# Increase health check timeout
# Edit deploy script: --health-timeout=10s (increase from 3s)
```

### Out of Disk Space

```bash
# Clean up old images
docker image prune -a

# Clean up stopped containers
docker container prune

# Check disk usage
docker system df
```

---

## Performance Tuning

### Resource Limits

```bash
docker run -d \
  --memory=512m \
  --cpus=1 \
  --memory-swap=512m \
  nexusshield-dashboard:latest
```

### Build Optimization

Use BuildKit for faster builds:
```bash
DOCKER_BUILDKIT=1 docker build -f frontend/dashboard/Dockerfile frontend/dashboard/
```

### Caching

Leverage Docker layer caching:
```bash
# Dependencies change rarely → cache them
COPY package*.json ./
RUN npm ci
# Source changes frequently → build after
COPY src ./
RUN npm run build
```

---

## Security Hardening

### Network

```bash
# Firewall: Only expose to trusted IPs
sudo ufw allow from 10.0.0.0/8 to any port 3000

# Or use reverse proxy (Nginx)
# And disable external access to port 3000
```

### Container

```bash
# Run as non-root
docker run -d \
  --user 1000:1000 \
  nexusshield-dashboard:latest

# Read-only filesystem
docker run -d \
  --read-only \
  --tmpfs /tmp \
  nexusshield-dashboard:latest
```

### Environment

```bash
# Don't expose sensitive data in logs
# Use secret management (e.g., HashiCorp Vault)
# Reference in deployment script:
API_URL=$(vault kv get -field=api_url secret/dashboard)
```

---

## Scaling & Load Balancing

### Multiple Instances

```bash
# Deploy on multiple ports
bash scripts/deploy/deploy_dashboard.sh host1 http://api:8080 3000
ssh host2 'bash scripts/deploy/deploy_dashboard.sh localhost http://api:8080 3001'

# Or use Docker Compose for orchestration
docker-compose -f frontend/docker-compose.dashboard.yml up -d
```

### Nginx Reverse Proxy

```nginx
upstream dashboard {
  server localhost:3000;
  server host2:3000;
}

server {
  listen 80;
  server_name dashboard.example.com;

  location / {
    proxy_pass http://dashboard;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
  }
}
```

---

## Rollback Procedures

### Quick Rollback (Previous Image)

```bash
# List available images
docker image ls | grep nexusshield-dashboard

# Run with specific version
docker rm -f nexusshield-dashboard-prod
docker run -d \
  -p 3000:3000 \
  nexusshield-dashboard:v1.2.3

# Or keep multiple tags
docker tag nexusshield-dashboard:latest nexusshield-dashboard:v1.2.5
```

### Via Git Tag

```bash
# Checkout specific commit
git checkout v1.2.3

# Rebuild and deploy
bash scripts/deploy/deploy_dashboard.sh localhost http://api:8080
```

---

## Monitoring & Observability

### Metrics Collection

```bash
# Container stats (live)
docker stats nexusshield-dashboard-prod

# Log shipping (example)
docker logs --follow nexusshield-dashboard-prod | \
  jq -R '. as $line | {timestamp: now|todate, message: $line}' | \
  curl -X POST -H "Content-Type: application/json" -d @- https://logs.example.com/api/logs
```

### Alert Setup

```bash
# Health check script (run via cron every 5 min)
#!/bin/bash
STATUS=$(docker inspect --format='{{.State.Health.Status}}' nexusshield-dashboard-prod)
if [ "$STATUS" != "healthy" ]; then
  # Send alert
  curl -X POST https://alerts.example.com/incident \
    -d "{\"service\": \"dashboard\", \"status\": \"unhealthy\"}"
fi
```

---

## FAQ

**Q: Can I use a container registry (Docker Hub, ECR)?**  
A: Yes! After building locally, push and deploy:
```bash
docker tag nexusshield-dashboard:latest myregistry/dashboard:latest
docker push myregistry/dashboard:latest
# Then update deploy script to use registry image
```

**Q: What if my remote host doesn't have Docker installed?**  
A: Use remote installation:
```bash
curl -fsSL https://get.docker.com | ssh user@host bash
```

**Q: Can I use Kubernetes instead?**  
A: Yes, with a deployment manifest. But this guide is optimized for single-host Docker.

**Q: How do I update the dashboard code?**  
A: Git pull, rebuild, redeploy:
```bash
git pull origin main
bash scripts/deploy/deploy_dashboard.sh production-host http://api:8080
```

**Q: What's the difference between localhost and remote?**  
A: The script auto-detects:
- **localhost:** Uses `docker` directly
- **Remote:** Uses `ssh` to execute commands remotely

---

## Checklist: Pre-Deployment Verification

- [ ] Docker installed on build machine
- [ ] Docker installed on production host
- [ ] SSH key-based auth configured (no password)
- [ ] Port 3000 available on production host
- [ ] Backend API URL confirmed and accessible
- [ ] Disk space available (~500MB)
- [ ] Firewall rules allow port 3000 (if external)
- [ ] Environment variables documented
- [ ] Rollback procedure tested
- [ ] Monitoring alerts configured

---

## Files Touched by Deployment

| File | Purpose |
|------|---------|
| `scripts/deploy/deploy_dashboard.sh` | Deployment orchestration |
| `frontend/dashboard/Dockerfile` | Container image definition |
| `frontend/dashboard/package.json` | Dependencies |
| `frontend/dashboard/src/` | React application source |
| `/etc/systemd/system/nexusshield-dashboard.service` | Auto-restart config |
| `.deployment_logs/` | Immutable audit trail |

---

## Support & References

**Documentation:**
- [Docker Official Docs](https://docs.docker.com/)
- [React Best Practices](https://react.dev/)
- [Node.js Production Guide](https://nodejs.org/en/docs/guides/nodejs-docker-webapp/)

**Related Issues:**
- #1681 - Unified CI-less Orchestrator
- #1682 - Frontend Deployment
- #1683 - API Integration

**Contact:**
- DevOps Team: devops@example.com
- On-Call: +1-555-ONECALL

---

**Last Updated:** 2026-03-10T14:00:00Z  
**Status:** ✅ Production Ready  
**Maintained By:** Infrastructure Team
