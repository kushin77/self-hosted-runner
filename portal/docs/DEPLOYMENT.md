# NexusShield Portal - Deployment Guide

**Version:** 1.0  
**Status:** Production Ready  
**Last Updated:** March 12, 2026

---

## Quick Start

### Prerequisites

- Node.js ≥18.0.0
- Docker (optional, for containerization)
- Git
- pnpm (or npm)

### Local Development

```bash
# Clone the repo (if not already there)
cd /home/akushnir/self-hosted-runner/portal

# Install dependencies
pnpm install

# Start development servers (API + Frontend)
pnpm portal:dev

# Portal will be available at:
# - Frontend: http://localhost:3000
# - API: http://localhost:5000
# - Health check: http://localhost:5000/health
```

### Production Build

```bash
# Build all packages
pnpm build:prod

# Test the production build
pnpm preview

# Create Docker image
pnpm docker:build

# Run Docker container
pnpm docker:run
```

---

## Docker Deployment

### Single Container

```bash
# Build
docker build -f portal/docker/Dockerfile -t nexusshield/portal:latest .

# Run
docker run \
  -p 3000:3000 \
  -p 5000:5000 \
  -e NODE_ENV=production \
  -e LOG_LEVEL=info \
  nexusshield/portal:latest
```

### Docker Compose

```bash
# Start all services
docker-compose -f portal/docker/docker-compose.yml up

# View logs
docker-compose logs -f

# Stop
docker-compose down
```

---

## Environment Variables

### API (.env in packages/api/)

```bash
# Execution environment
NODE_ENV=production              # development|production
LOG_LEVEL=info                   # debug|info|warn|error
PORT=5000
HOST=0.0.0.0

# API Configuration
API_URL=http://localhost:5000
API_TIMEOUT=30000                # milliseconds
MAX_REQUEST_SIZE=50mb

# Cloud integrations (when enabled)
GCP_PROJECT_ID=your-project
AWS_REGION=us-east-1
VAULT_ADDR=http://vault:8200

# Database (future)
# DATABASE_URL=postgresql://user:pass@localhost/portal

# Monitoring
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9090
```

### Frontend (.env in packages/frontend/)

```bash
# API endpoint
VITE_API_URL=http://localhost:5000
VITE_API_TIMEOUT=30000

# UI Configuration
VITE_LOG_LEVEL=info
VITE_THEME=dark                  # dark|light

# Feature flags
VITE_ENABLE_DIAGRAMS=true
VITE_ENABLE_ANALYTICS=false
```

---

## Kubernetes Deployment

### Helm Chart (Recommended)

```bash
# Create namespace
kubectl create namespace portal

# Install Helm chart
helm install nexusshield-portal ./helm/portal \
  -n portal \
  --values helm/values-production.yaml
```

### Manual YAML

```yaml
# 1. Portal Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nexusshield-portal
  namespace: portal
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nexusshield-portal
  template:
    metadata:
      labels:
        app: nexusshield-portal
    spec:
      containers:
      - name: api
        image: nexusshield/portal:latest
        ports:
        - containerPort: 5000
          name: api
        env:
        - name: NODE_ENV
          value: "production"
        - name: LOG_LEVEL
          value: "info"
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 5

      - name: frontend
        image: nexusshield/portal:latest
        ports:
        - containerPort: 3000
          name: web
        env:
        - name: VITE_API_URL
          value: "https://api.example.com"

---
# 2. Service
apiVersion: v1
kind: Service
metadata:
  name: nexusshield-portal
  namespace: portal
spec:
  type: LoadBalancer
  selector:
    app: nexusshield-portal
  ports:
  - name: api
    port: 5000
    targetPort: 5000
  - name: web
    port: 3000
    targetPort: 3000

---
# 3. HorizontalPodAutoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nexusshield-portal
  namespace: portal
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nexusshield-portal
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

---

## GitOps Deployment

### Using GitLab CI/CD

The `.gitlab-ci.yml` file automates building and deploying:

```bash
# Trigger deployment by pushing to main
git push origin main

# Pipeline stages:
# 1. Install dependencies
# 2. Lint code
# 3. Build packages
# 4. Run tests
# 5. Build Docker image
# 6. Push to registry
# 7. Deploy to staging (auto)
# 8. Deploy to production (manual)
```

### Using Flux CD

```bash
# Install Flux
flux bootstrap github \
  --owner=kushin77 \
  --repo=self-hosted-runner \
  --path=portal/k8s

# Flux will auto-sync when you push changes
```

---

## Configuration

### Reverse Proxy (Nginx)

```nginx
upstream portal_api {
  server localhost:5000;
  keepalive 32;
}

upstream portal_web {
  server localhost:3000;
  keepalive 32;
}

server {
  listen 443 ssl http2;
  server_name portal.example.com;

  ssl_certificate /etc/ssl/certs/nexusshield.crt;
  ssl_certificate_key /etc/ssl/private/nexusshield.key;

  # API
  location /api/ {
    proxy_pass http://portal_api;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }

  # Frontend
  location / {
    proxy_pass http://portal_web;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
  }
}
```

### Load Balancer (AWS ALB)

```
Target Group 1 (API)
  - Port: 5000
  - Health check: /health
  - Instances: [api-1, api-2, api-3]

Target Group 2 (Web)
  - Port: 3000
  - Health check: /
  - Instances: [web-1, web-2, web-3]

ALB Listener (443)
  - Path /api/* → Target Group 1
  - Path / → Target Group 2
```

---

## Health Monitoring

### Health Check Endpoints

```bash
# API health
curl http://localhost:5000/health

# Expected response
{
  "success": true,
  "data": {
    "status": "healthy",
    "timestamp": "2026-03-12T10:00:00Z",
    "version": "v1"
  }
}
```

### Prometheus Metrics (Coming Soon)

```
http://localhost:9090/metrics
```

### Server Logs

```bash
# View logs from stdout
docker logs <container-id>

# View logs from file
tail -f logs/portal-api.log
tail -f logs/portal-web.log
```

---

## Upgrade Process

### Pre-upgrade Checklist

- [ ] Read release notes
- [ ] Backup database (if used)
- [ ] Test in staging
- [ ] Plan maintenance window
- [ ] Notify users

### Upgrade Steps

```bash
# 1. Pull latest code
git pull origin main

# 2. Build new version
pnpm build:prod

# 3. Build Docker image
docker build -t nexusshield/portal:v1.1.0 .

# 4. Test locally
docker run -p 3000:3000 -p 5000:5000 nexusshield/portal:v1.1.0

# 5. Push to registry
docker push nexusshield/portal:v1.1.0

# 6. Update deployment
# Option A: Kubernetes
kubectl set image deployment/nexusshield-portal \
  nexusshield-portal=nexusshield/portal:v1.1.0 \
  -n portal

# Option B: Docker Compose
docker-compose -f portal/docker/docker-compose.yml up -d

# 7. Monitor logs
docker logs -f <container>

# 8. Verify
curl http://localhost:5000/health
```

---

## Security Hardening

### TLS/HTTPS

```nginx
# Use modern SSL/TLS
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```

### CORS

```javascript
// In packages/api/src/app.ts
app.use(cors({
  origin: 'https://portal.example.com',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE']
}))
```

### Rate Limiting (Coming Soon)

```javascript
const rateLimit = require('express-rate-limit')
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // requests per windowMs
})
app.use('/api/', limiter)
```

### Secrets Management

```bash
# All secrets should come from:
# 1. Environment variables (injected by Kubernetes/Docker Compose)
# 2. Vault (via init container)
# 3. Cloud KMS (GCP KMS, AWS Secrets Manager)

# NEVER hardcode secrets in code or config files
```

---

## Troubleshooting

### Issue: Port Already in Use

```bash
# Find process using port
lsof -i :5000
lsof -i :3000

# Kill process
kill -9 <PID>

# Or use different port
PORT=5001 pnpm -C packages/api dev
```

### Issue: Dependencies Not Installing

```bash
# Clear cache
rm -rf node_modules pnpm-lock.yaml

# Reinstall
pnpm install
```

### Issue: Build Failures

```bash
# Check TypeScript errors
pnpm type-check

# View full error
pnpm build 2>&1 | head -50
```

### Issue: API Not Responding

```bash
# Check API is running
ps aux | grep node

# Check port binding
netstat -tulpn | grep 5000

# View logs
pnpm -C packages/api dev  # run in foreground to see logs
```

---

## Maintenance

### Scheduled Tasks

```bash
# Weekly: Run tests
0 2 * * 0 pnpm test

# Daily: Check for updates
0 3 * * * npm update --dry-run

# Monthly: Dependency audit
0 4 1 * * npm audit
```

### Backup Strategy

For future database deployments:

```bash
# Nightly backup
0 2 * * * pg_dump portal | gzip > /backups/portal-$(date +%Y%m%d).sql.gz

# Weekly archive to S3
0 3 * * 0 aws s3 sync /backups s3://backups/portal/
```

---

## Performance Tuning

### Node.js

```bash
# Increase max file descriptors
ulimit -n 65536

# Enable clustering
NODE_CLUSTER=true pnpm start
```

### Database (Future)

```sql
-- Create indexes
CREATE INDEX idx_deployments_status ON deployments(status);
CREATE INDEX idx_secrets_expires ON secrets(expires_at);

-- Analyze query performance
EXPLAIN ANALYZE SELECT * FROM deployments;
```

---

## Support & Resources

- **Documentation:** `/portal/docs/`
- **Source Code:** `/portal/packages/`
- **Issues:** GitHub Issues
- **Logs:** Check `/logs/` or container logs

---

**Next Steps:**
1. Deploy to development environment
2. Run smoke tests
3. Deploy to staging
4. Get team approval
5. Deploy to production

**Version History:**
- v1.0 (2026-03-12): Initial deployment guide
