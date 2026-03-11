# NexusShield Dashboard Deployment - Quick Reference Card

**Status:** ✅ Production Ready  
**Last Updated:** 2026-03-10T14:00:00Z  
**Framework:** CI-Less Direct Deploy

---

## One-Liners

### Deploy Locally
```bash
bash scripts/deploy/deploy_dashboard.sh
```

### Deploy to Remote
```bash
bash scripts/deploy/deploy_dashboard.sh production.example.com https://api.example.com 3000
```

### View Logs
```bash
docker logs -f nexusshield-dashboard-prod
```

### Check Status
```bash
docker inspect --format='{{.State.Health.Status}}' nexusshield-dashboard-prod
```

### Stop Dashboard
```bash
docker stop nexusshield-dashboard-prod
```

### Restart Dashboard
```bash
docker restart nexusshield-dashboard-prod
```

---

## Common Tasks

### Test Health Endpoint
```bash
curl http://localhost:3000/health
# Response: {"status": "healthy"}
```

### View Container Details
```bash
docker inspect nexusshield-dashboard-prod | jq '.'
```

### Execute Command Inside Container
```bash
docker exec nexusshield-dashboard-prod ps aux
```

### Clean Up Old Images
```bash
docker image prune -a --filter "until=24h"
```

### Rebuild Image
```bash
docker build -f frontend/dashboard/Dockerfile -t nexusshield-dashboard:latest frontend/dashboard/
```

### Deploy with Custom API
```bash
# Edit API_URL in deploy script or pass via env
bash scripts/deploy/deploy_dashboard.sh localhost https://api.staging.com 3000
```

### Enable Debug Logging
```bash
docker run -d \
  -e REACT_APP_LOG_LEVEL=debug \
  -p 3000:3000 \
  nexusshield-dashboard:latest
```

---

## Debugging

### Port Already in Use
```bash
sudo lsof -i :3000
sudo kill -9 <PID>
```

### Container Won't Start
```bash
docker logs nexusshield-dashboard-prod 2>&1 | tail -50
docker run -it nexusshield-dashboard:latest node server.js
```

### API Connection Failed
```bash
docker exec nexusshield-dashboard-prod curl http://api-backend:8080/health
```

### Health Check Stuck
```bash
docker inspect --format='{{json .State.Health}}' nexusshield-dashboard-prod | jq
```

### Disk Space Issues
```bash
docker system df
docker image prune -a
docker container prune
```

---

## Load Balancing (Multi-Instance)

### Deploy 3 Instances with Nginx
```bash
docker-compose -f frontend/docker-compose.loadbalancer.yml up -d
```

### Access via Load Balancer
```bash
http://localhost:80  # HTTP (redirects to HTTPS)
https://localhost:443  # HTTPS
```

### Scale to 5 Instances
```bash
docker-compose -f frontend/docker-compose.loadbalancer.yml up -d --scale dashboard=5
```

### Monitor Load Balancer Status
```bash
curl http://localhost/nginx_status  # Nginx metrics
```

---

## Environment Variables

| Variable | Example | Notes |
|----------|---------|-------|
| `REACT_APP_API_URL` | `http://api:8080` | Backend URL |
| `REACT_APP_LOG_LEVEL` | `info` | debug, info, warn, error |
| `PORT` | `3000` | Server port |
| `NODE_ENV` | `production` | production or development |

### Set on Deployment
```bash
docker run -d \
  -e REACT_APP_API_URL=http://backend:8080 \
  -e REACT_APP_LOG_LEVEL=debug \
  -p 3000:3000 \
  nexusshield-dashboard:latest
```

---

## Systemd Integration

### Auto-Start on Reboot
```bash
sudo tee /etc/systemd/system/nexusshield-dashboard.service >/dev/null <<EOF
[Unit]
Description=NexusShield Dashboard
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/docker run -p 3000:3000 nexusshield-dashboard:latest
Restart=unless-stopped

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nexusshield-dashboard.service
sudo systemctl start nexusshield-dashboard.service
```

### Check Service Status
```bash
sudo systemctl status nexusshield-dashboard
sudo journalctl -u nexusshield-dashboard -f  # Follow logs
```

---

## Performance Monitoring

### CPU/Memory Usage
```bash
docker stats nexusshield-dashboard-prod
# Watch real-time resource usage
```

### Request Metrics
```bash
# From Nginx logs
docker logs dashboard-lb | grep "GET\|POST"

# Count requests per second
docker logs dashboard-lb | grep -c "HTTP"
```

### Response Time
```bash
curl -w "Response: %{time_total}s\n" http://localhost:3000/
```

---

## Backup & Restore

### Backup Container
```bash
docker commit nexusshield-dashboard-prod nexusshield-dashboard:backup-2026-03-10
docker tag nexusshield-dashboard:backup-2026-03-10 nexusshield-dashboard:backup
```

### Restore from Backup
```bash
docker rm -f nexusshield-dashboard-prod
docker run -d -p 3000:3000 nexusshield-dashboard:backup
```

### Export Logs
```bash
mkdir -p backup/dashboard-logs-2026-03-10
docker logs nexusshield-dashboard-prod > backup/dashboard-logs-2026-03-10/app.log 2>&1
```

---

## Security Checklist

- [ ] HTTPS enabled (TLS 1.3+)
- [ ] Firewall: Port 3000 restricted to internal IPs
- [ ] Health checks enabled and passing
- [ ] Restart policy: `unless-stopped`
- [ ] Non-root user (if configured)
- [ ] Read-only filesystem (if needed)
- [ ] Resource limits set (memory, CPU)
- [ ] Logs monitored and rotated

---

## Audit Trail

### View Deployment History
```bash
cat .deployment_logs/$(ls -t .deployment_logs | head -1)
```

### Find All Deployments Today
```bash
find .deployment_logs -mtime 0 -type f
```

### Search for Specific Deployment
```bash
grep -l "2026-03-10" .deployment_logs/*.json | head
```

---

## Troubleshooting Decision Tree

```
Dashboard not accessible?
├─ Check if container is running
│  └─ docker ps | grep nexusshield
│
├─ Check port mapping
│  └─ docker port nexusshield-dashboard-prod
│
├─ Check firewall
│  └─ sudo ufw status | grep 3000
│
└─ Check health
   └─ docker inspect --format='{{.State.Health.Status}}'

Health check failing?
├─ Check logs
│  └─ docker logs nexusshield-dashboard-prod
│
├─ Test manually
│  └─ docker exec nexusshield-dashboard-prod curl localhost:3000/health
│
└─ Increase timeout
   └─ Edit deploy script: --health-timeout=10s

API unreachable?
├─ Verify API URL
│  └─ curl http://api-backend:8080/health
│
├─ Check container network
│  └─ docker inspect nexusshield-dashboard-prod | jq '.NetworkSettings'
│
└─ Test from inside container
   └─ docker exec nexusshield-dashboard-prod curl http://api:8080/health
```

---

## Useful Commands Summary

| Task | Command |
|------|---------|
| Deploy | `bash scripts/deploy/deploy_dashboard.sh` |
| Logs | `docker logs -f nexusshield-dashboard-prod` |
| Status | `docker ps` / `docker stats` |
| Health | `curl http://localhost:3000/health` |
| Restart | `docker restart nexusshield-dashboard-prod` |
| Stop | `docker stop nexusshield-dashboard-prod` |
| Remove | `docker rm -f nexusshield-dashboard-prod` |
| Shell | `docker exec -it nexusshield-dashboard-prod sh` |
| Rebuild | `docker build -f frontend/dashboard/Dockerfile frontend/dashboard/` |
| Cleanup | `docker system prune -a` |

---

## Support

**Documentation:** See [DASHBOARD_DEPLOYMENT_GUIDE.md](DASHBOARD_DEPLOYMENT_GUIDE.md)  
**Issues:** #1682 - Frontend Deployment  
**Contact:** devops@example.com

---

**Print this page and post it on your desk!** 📋
