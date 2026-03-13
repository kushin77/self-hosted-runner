# Portal Proxy Configuration Guide

## Overview

This guide documents the proxy configuration for the Portal frontend, API, and GitPeak integration services. It ensures proper DNS resolution, environment-aware routing, and auth header forwarding.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (Port 3000 / 3002)                                 │
│ - Vite dev server with dynamic '/api' proxy                 │
│ - Uses VITE_API_URL environment variable                    │
└───────────┬─────────────────────────────────────────────────┘
            │ /api requests
            ▼
┌─────────────────────────────────────────────────────────────┐
│ Portal API (Port 5000)                                      │
│ - Express.js server                                         │
│ - Mounts GitPeak routes at /api/v1/gitpeak                  │
│ - Forwards requests to GitPeak backend                      │
└───────────┬─────────────────────────────────────────────────┘
            │ /api/v1/gitpeak/* requests
            ▼
┌─────────────────────────────────────────────────────────────┐
│ GitPeak Backend (Port 8000/8001)                            │
│ - Python/FastAPI service                                    │
│ - Uses GITPEAK_BACKEND_URL environment variable            │
│ - Responds to /repos, /health endpoints                     │
└─────────────────────────────────────────────────────────────┘
```

## Key Environment Variables

### Frontend (portal/packages/frontend/vite.config.ts)
```
VITE_API_URL via docker-compose.yml: Controls proxy target for /api routes
  Default: http://localhost:5000 (local dev)
  Production: Use .env file with production URL
```

### API Server (portal/packages/api/src/routes/gitpeak.ts)
```
GITPEAK_BACKEND_URL: Controls where the proxy forwards requests
  Default: http://127.0.0.1:8001
  Docker: http://gitpeak-backend:8001 (service name resolution)
```

## Docker Compose Configuration

File: `portal/docker/docker-compose.yml`

### Service Routing
1. **portal-api** (Port 5000)
   - Serves API endpoints
   - Mounts GitPeak proxy routes
   - Environment: `GITPEAK_BACKEND_URL=http://gitpeak-backend:8000`

2. **portal-frontend** (Port 3000)
   - Vite dev server
   - Environment: `VITE_API_URL=http://localhost:5000` (can be overridden)
   - Proxies /api → portal-api

3. **gitpeak-backend** (Port 8001)
   - FastAPI service
   - Connected via docker network
   - No special proxy configuration needed

### Environment Variable Precedence

**Frontend Proxy (vite.config.ts):**
```typescript
target: process.env.VITE_API_URL || 'http://localhost:5000'
```
- Uses `VITE_API_URL` if set
- Falls back to localhost for local development
- Configured in docker-compose.yml

**API Proxy (routes/gitpeak.ts):**
```typescript
const GITPEAK_BACKEND = process.env.GITPEAK_BACKEND_URL || 'http://127.0.0.1:8001'
```
- Uses `GITPEAK_BACKEND_URL` if set
- Falls back to localhost:8001 for local development
- Should be `http://gitpeak-backend:8000` in docker

## Network Modes

### Local Development
```bash
# Uses localhost and port mapping
VITE_API_URL=http://localhost:5000
GITPEAK_BACKEND_URL=http://127.0.0.1:8001
```

### Docker Compose
```bash
# Uses service names (DNS resolution via bridge network)
VITE_API_URL=http://localhost:5000  # from browser perspective
GITPEAK_BACKEND_URL=http://gitpeak-backend:8000  # from api container
```

### Production
```bash
# Use actual hostnames/IPs in .env file
VITE_API_URL=https://portal.example.internal:5000
GITPEAK_BACKEND_URL=https://gitpeak.example.internal:8000
```

## Auth Header Forwarding

The GitPeak proxy (routes/gitpeak.ts) forwards authentication:
```typescript
function forwardHeaders(req: Request) {
  const headers: any = { 'content-type': 'application/json' }
  const auth = (req.headers?.authorization as string) || 'Bearer test-token'
  headers.authorization = auth
  return headers
}
```

- Extracts `Authorization` header from incoming request
- Forwards to GitPeak backend
- Defaults to `Bearer test-token` if not present

## Troubleshooting

### Issue: Frontend Cannot Reach API
**Symptom:** Browser error "Failed to fetch /api/..."

**Resolution:**
1. Check `VITE_API_URL` is set correctly in `.env`
2. Verify Portal API is running on expected port
3. Check browser network tab for actual request URL
4. If using localhost, ensure api container is accessible

### Issue: API Cannot Reach GitPeak Backend
**Symptom:** `/api/v1/gitpeak/health` returns connection error

**Resolution:**
1. Check `GITPEAK_BACKEND_URL` environment variable
2. Verify GitPeak backend service is running
3. Check docker network connectivity:
   ```bash
   docker exec portal-api curl http://gitpeak-backend:8000/
   ```
4. If using localhost, ensure ports are mapped correctly

### Issue: DNS Resolution in Docker
**Symptom:** "Cannot resolve service name"

**Resolution:**
1. Ensure services are on same docker network (gitpeak)
2. Use service names, not IPs, in docker containers
3. Use localhost:port from host machine
4. Verify docker-compose.yml has `networks: gitpeak`

## Configuration Files

- `portal/docker/.env.example` - Template for local dev
- `portal/docker/.env.production` - Production configuration template
- `portal/packages/frontend/vite.config.ts` - Frontend proxy setup
- `portal/packages/api/src/routes/gitpeak.ts` - API backend proxy

## Summary

✅ **Fixed Issues:**
- [x] Frontend vite.config.ts now uses environment variable for API proxy
- [x] API routes support configurable GitPeak backend URL
- [x] Docker Compose properly configures all proxies
- [x] Auth headers forwarded through proxy chain

✅ **Best Practices Implemented:**
- Use environment variables for endpoint configuration
- Docker uses service names (DNS), not IPs
- Fallback to localhost for local development
- Auth headers properly forwarded
- Comprehensive error handling
