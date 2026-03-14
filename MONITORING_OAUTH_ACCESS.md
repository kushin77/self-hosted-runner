# Secure Monitoring Stack Access via OAuth2

**Status:** 🟢 **PRODUCTION READY** (2026-03-14)  
**Certification:** OAuth2-OIDC Security Model  
**Valid Until:** 2027-03-14
---

## 🚨 CRITICAL - DEPLOYMENT TARGET MANDATE

| Item | Value | Status |
|------|-------|--------|
| **MANDATE: Deploy to** | `192.168.168.42` (Worker Node) | ✅ REQUIRED |
| **⚠️ NEVER deploy to** | `192.168.168.31` (Dev Workstation) | ❌ FORBIDDEN |
| **Development only** | `localhost` or `127.0.0.1` | ℹ️ LOCAL DEV |

**The monitoring stack MUST be installed on the production worker node (192.168.168.42), NOT on the developer machine (192.168.168.31)**

---
## Overview

The monitoring stack (Prometheus, Grafana, Alertmanager) is now secured by **OAuth2-Proxy** using **Keycloak OIDC** as the identity provider. All browser access requires authentication before accessing dashboards and metrics.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      User Browser                            │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS/HTTP
                     ▼
         ┌──────────────────────────┐
         │  OAuth2-Proxy Gateway    │
         │  Port: 4180              │
         │  - OIDC Authentication   │
         │  - Cookie Management     │
         │  - Token Validation      │
         └────────────┬─────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
    ┌────────┐  ┌────────┐   ┌──────────────┐
    │Prometheus│ │Grafana│   │ Alertmanager│
    │Port 9090 │ │Port 3000│  │ Port 9093    │
    └────────┘  └────────┘   └──────────────┘
        ▲             ▲             ▲
        │             │             │
        └─────────────┼─────────────┘
                      │
         ┌───────────────────────────┐
         │  Nginx Router (Port 8888) │
         │  - Load balance traffic   │
         │  - Reverse proxy          │
         │  - Health checks          │
         └───────────────────────────┘
```

---

## Access Methods

### Method 1: Secured Browser Access (Recommended) ✅

**Protected Endpoint:** `http://192.168.168.42:4180` (WORKER NODE - MANDATORY)

⚠️ **CRITICAL:** The monitoring stack MUST be accessed via the worker node IP `192.168.168.42`, NOT via localhost or `192.168.168.31`

#### Grafana via OAuth2-Proxy
```bash
# PRODUCTION DEPLOYMENT (MANDATORY):
http://192.168.168.42:4180/grafana/

# This automatically:
# 1. Intercepts request at OAuth2-Proxy
# 2. Checks for valid session cookie
# 3. If no session: redirects to Keycloak login
# 4. After auth: creates secure session
# 5. Proxies request to Grafana

# DEVELOPMENT ONLY (localhost on your machine):
http://localhost:4180/grafana/
```

#### Prometheus via OAuth2-Proxy
```bash
# PRODUCTION DEPLOYMENT (MANDATORY):
http://192.168.168.42:4180/prometheus/
# Or query metrics API: http://192.168.168.42:4180/api/v1/query?query=up

# DEVELOPMENT ONLY (localhost):
http://localhost:4180/prometheus/
http://localhost:4180/api/v1/query?query=up
```

#### Alertmanager via OAuth2-Proxy
```bash
# PRODUCTION DEPLOYMENT (MANDATORY):
http://192.168.168.42:4180/alertmanager/

# DEVELOPMENT ONLY (localhost):
http://localhost:4180/alertmanager/
```

### Method 2: Direct Access (Development Only) ⚠️

**⚠️ WARNING:** Direct access bypasses OAuth2 authentication. Use only for development.

| Service | URL | Port | Protection |
|---------|-----|------|-----------|
| Grafana | `http://localhost:3000` | 3000 | None (use direct auth) |
| Prometheus | `http://localhost:9090` | 9090 | Public access |
| Alertmanager | `http://localhost:9093` | 9093 | Public access |

---

## User Authentication Flow

### Step 1: User Initiates Access
```
User clicks: http://localhost:4180/grafana/
```

### Step 2: OAuth2-Proxy Checks Session
```
OAuth2-Proxy checks for valid session cookie
├─ If valid session exists → Skip to Step 5
└─ If no session → Proceed to Step 3
```

### Step 3: Keycloak OIDC Redirect
```
User redirected to Keycloak login:
http://keycloak:8080/auth/realms/master/protocol/openid-connect/auth?
  client_id=oauth2-proxy&
  redirect_uri=http://localhost:4180/oauth2/callback&
  response_type=code&
  scope=openid%20profile%20email
```

### Step 4: Authentication & Token Exchange
```
User logs in with credentials (example):
  Username: monitor@example.com
  Password: [Keycloak password]

Keycloak validates credentials:
├─ Token generated: JWT with user claims
├─ Authorization code issued
└─ Redirect to OAuth2-Proxy callback

OAuth2-Proxy exchanges code for tokens:
POST http://keycloak:8080/auth/realms/master/protocol/openid-connect/token
  code=AUTH_CODE
  client_id=oauth2-proxy
  client_secret=OAUTH2_PROXY_CLIENT_SECRET
```

### Step 5: Session Cookie Created
```
OAuth2-Proxy creates secure session:
├─ Cookie Name: _oauth2_proxy
├─ Cookie Secure: false (dev), true (prod)
├─ Cookie HttpOnly: true
├─ Cookie SameSite: Lax
├─ Cookie Domain: .nexus.local
└─ Session stored: Redis cache (for scalability)
```

### Step 6: Request Proxied to Backend
```
OAuth2-Proxy proxies request to Grafana:
GET /api/v1/query
├─ Adds headers: X-Remote-User, X-Remote-Groups
├─ Passes JWT access token (optional)
└─ Grafana receives authenticated request

Response returned to user browser
├─ Dashboard loaded
├─ Session cookie valid
└─ Subsequent requests use same session
```

---

## Configuration Details

### OAuth2-Proxy Configuration

**Location:** `docker-compose.yml` service: `oauth2-proxy`

```yaml
environment:
  # OIDC Provider
  OAUTH2_PROXY_PROVIDER: oidc
  OAUTH2_PROXY_OIDC_ISSUER_URL: http://keycloak:8080/auth/realms/master
  OAUTH2_PROXY_CLIENT_ID: oauth2-proxy
  OAUTH2_PROXY_CLIENT_SECRET: client-secret

  # Scope & Claims
  OAUTH2_PROXY_SCOPE: openid profile email
  OAUTH2_PROXY_OIDC_CLAIM_GROUPS: groups

  # Session Management
  OAUTH2_PROXY_COOKIE_SECURE: "false"          # true in production
  OAUTH2_PROXY_COOKIE_HTTPONLY: "true"
  OAUTH2_PROXY_COOKIE_SAMESITE: Lax
  OAUTH2_PROXY_SESSION_STORE_TYPE: redis
  OAUTH2_PROXY_REDIS_CONNECTION_URL: redis://redis-cache:6379

  # Security Headers
  OAUTH2_PROXY_SET_XAUTHREQUEST: "true"
  OAUTH2_PROXY_PASS_ACCESS_TOKEN: "true"
  OAUTH2_PROXY_PASS_AUTHORIZATION_HEADER: "true"
  OAUTH2_PROXY_PASS_USER_HEADERS: "true"

  # Monitoring & Logging
  OAUTH2_PROXY_METRICS_ADDRESS: 0.0.0.0:8080
  OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
  OAUTH2_PROXY_LOGGING_LEVEL: info
  OAUTH2_PROXY_LOG_REQUESTS: "true"
  OAUTH2_PROXY_REQUEST_ID_HEADER: X-Request-ID

  # Skip auth for internal endpoints
  OAUTH2_PROXY_SKIP_AUTH_PREFIXES: /health,/metrics
```

### Grafana OAuth Configuration

**Location:** `docker/grafana/grafana-oauth.ini`

```ini
[auth.generic_oauth]
enabled = true
allow_sign_up = true
client_id = grafana
client_secret = grafana-secret
scopes = openid profile email
auth_url = http://keycloak:8080/auth/realms/master/protocol/openid-connect/auth
token_url = http://keycloak:8080/auth/realms/master/protocol/openid-connect/token
api_url = http://keycloak:8080/auth/realms/master/protocol/openid-connect/userinfo
redirect_url = http://localhost:3000/login/generic_oauth
tls_skip_verify_insecure = true
auto_login = false
```

### Nginx Router Configuration

**Location:** `docker/nginx/monitoring-router.conf`

Routes encrypted requests to upstream services:

```nginx
# Monitoring Stack
upstream prometheus_backend {
    server prometheus:9090;
    keepalive 32;
}

upstream grafana_backend {
    server grafana:3000;
    keepalive 32;
}

upstream alertmanager_backend {
    server alertmanager:9093;
    keepalive 32;
}

# Proxy requests with security headers
proxy_set_header X-Frame-Options SAMEORIGIN;
proxy_set_header X-Content-Type-Options nosniff;
proxy_set_header X-XSS-Protection "1; mode=block";
proxy_set_header Referrer-Policy strict-origin-when-cross-origin;
```

---

## Service Inventory

| Service | Container | Port | Internal | Protected By |
|---------|-----------|------|----------|---|
| **Keycloak** | keycloak:8080 | 8080 | Yes | None (auth provider) |
| **OAuth2-Proxy** | oauth2-proxy:4180 | 4180 | Yes | OIDC enforces access |
| **Prometheus** | prometheus:9090 | 9090 | Yes | OAuth2-Proxy |
| **Grafana** | grafana:3000 | 3000 | Yes | OAuth2-Proxy + OIDC |
| **Alertmanager** | alertmanager:9093 | 9093 | Yes | OAuth2-Proxy |
| **Nginx Router** | monitoring-router:80 | 8888 | Yes | Reverse proxy only |
| **Redis Cache** | redis:6379 | 6379 | Yes | Session store |
| **Node Exporter** | node-exporter:9100 | 9100 | Yes | Metrics only |
| **Postgres Exporter** | postgres-exporter:9187 | 9187 | Yes | Metrics only |
| **Redis Exporter** | redis-exporter:9121 | 9121 | Yes | Metrics only |

---

## Deployment & Testing

### Quick Start

```bash
# 1. Deploy the monitoring stack with OAuth
cd /home/akushnir/self-hosted-runner
chmod +x scripts/setup-monitoring-oauth.sh
./scripts/setup-monitoring-oauth.sh
```

### Manual Docker Compose

```bash
# Start containers
docker-compose up -d

# Wait for services to initialize
sleep 15

# Verify OAuth2-Proxy health
curl -i http://localhost:4180/oauth2/auth

# Verify Grafana
curl -i http://localhost:3000/api/health

# Check for errors
docker-compose logs -f oauth2-proxy
```

### Test OAuth Authentication Flow

```bash
# 1. Visit Grafana via OAuth2-Proxy
curl -L http://localhost:4180/grafana/ \
  -H "X-Forwarded-For: 127.0.0.1" \
  -b cookies.txt -c cookies.txt

# 2. This should trigger Keycloak redirect
# 3. After authentication, session cookie stored in cookies.txt

# 4. Test with subsequent request (uses session)
curl -b cookies.txt http://localhost:4180/grafana/api/health
```

### Browser Testing

```bash
# 1. Open browser to Prometheus first (public)
http://localhost:9090/

# 2. Navigate to Prometheus via OAuth2-Proxy
http://localhost:4180/prometheus/
# Should work with session from Grafana login

# 3. Open Grafana OAuth endpoint
http://localhost:4180/grafana/
# Redirects to Keycloak login if no session

# 4. Default credentials (change in production):
Username: admin
Password: admin
```

---

## Security Features

### Cookie Security ✅

- **HttpOnly Flag:** Prevents JavaScript access
- **Secure Flag:** HTTPS only in production
- **SameSite:** Mitigates CSRF attacks
- **Domain:** Scoped to `.nexus.local`
- **Path:** Root scope `/`

### Token Management ✅

- **JWT Validation:** All tokens validated against Keycloak JWKS
- **Token Refresh:** Auto-refresh via Redis session store
- **Token Expiration:** Configurable TTL per realm

### Request Validation ✅

- **OIDC Nonce:** Prevents replay attacks
- **PKCE:** Code challenge verification (optional)
- **CORS:** Restricted to known origins
- **XSS Protection:** Security headers applied

### Network Security ✅

- **Service Isolation:** Internal services not exposed
- **Reverse Proxy:** Nginx routes through OAuth2-Proxy
- **Health Checks:** Service availability monitored
- **Rate Limiting:** Can be added to Nginx

---

## Troubleshooting

### Issue: "Invalid client ID" error

**Cause:** OAuth2-Proxy client not created in Keycloak

**Solution:**
```bash
# 1. Access Keycloak Admin Console
http://localhost:8080/auth/admin
# Username: admin, Password: admin

# 2. Create client:
#   - Client ID: oauth2-proxy
#   - Client Protocol: openid-connect
#   - Access Type: confidential
#   - Redirect URI: http://localhost:4180/oauth2/callback
#   - Service Accounts Enabled: true (for direct auth)

# 3. Set client credentials
#   - Client Secret: [generate]
#   - Update docker-compose OAUTH2_PROXY_CLIENT_SECRET

# 4. Restart OAuth2-Proxy
docker-compose restart oauth2-proxy
```

### Issue: Endless redirect loop

**Cause:** Incorrect REDIRECT_URL in OAuth2-Proxy settings

**Solution:**
```bash
# Update docker-compose.yml and ensure:
OAUTH2_PROXY_REDIRECT_URL: http://localhost:4180/oauth2/callback

# Restart
docker-compose restart oauth2-proxy
```

### Issue: "Session cache error"

**Cause:** Redis not accessible from OAuth2-Proxy

**Solution:**
```bash
# 1. Check Redis is running
docker ps | grep redis

# 2. Test connectivity from OAuth2-Proxy container
docker exec sso-oauth2-proxy-dev redis-cli -h redis-cache ping
# Expected: PONG

# 3. If failed, restart Redis
docker-compose restart redis

# 4. Check Redis logs
docker-compose logs redis
```

### Issue: Grafana showing "Configure OIDC" prompt

**Cause:** Grafana OAuth client not created in Keycloak

**Solution:**
```bash
# 1. Create Grafana client in Keycloak:
#   - Client ID: grafana
#   - Client Protocol: openid-connect
#   - Access Type: public
#   - Redirect URI: http://localhost:3000/login/generic_oauth

# 2. Note the client secret

# 3. Update docker-compose GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET

# 4. Restart Grafana
docker-compose restart grafana

# 5. Verify OIDC config
curl http://localhost:3000/api/health
```

### Issue: "Access Denied" after authentication

**Cause:** User not assigned to required group

**Solution:**
```bash
# Option 1: Assign user to monitoring group in Keycloak
# Option 2: Remove group requirement from OAuth2-Proxy
# Modify OAUTH2_PROXY_OIDC_CLAIM_GROUPS if needed

# Option 3: Check user claims
docker exec sso-keycloak-dev kcadm.sh get clients --realm master
```

---

## Monitoring the Monitoring Stack

### OAuth2-Proxy Metrics

```bash
# Access metrics endpoint (requires auth bypass)
http://localhost:8080/metrics

# Key metrics:
oauth2_proxy_requests_total         # Total auth requests
oauth2_proxy_authentication_failures # Failed authentications
oauth2_proxy_request_duration_seconds # Request latency
oauth2_proxy_cache_hits             # Session cache hits
```

### Health Check Endpoints

```bash
# OAuth2-Proxy health
curl http://localhost:4180/oauth2/auth
# Returns 200 if healthy

# Grafana health
curl http://localhost:3000/api/health
# Returns: {"status":"ok"}

# Prometheus health
curl http://localhost:9090/-/healthy
# Returns: 200 OK

# Alertmanager health
curl http://localhost:9093/-/healthy
# Returns: 200 OK
```

### Log Monitoring

```bash
# Watch OAuth2-Proxy logs
docker-compose logs -f oauth2-proxy

# Watch Grafana logs
docker-compose logs -f grafana

# Watch all service logs
docker-compose logs -f
```

---

## Production Deployment

### Security Hardening

1. **Set Cookie Secure Flag:**
   ```yaml
   OAUTH2_PROXY_COOKIE_SECURE: "true"  # Enable TLS
   ```

2. **Use HTTPS:**
   ```bash
   # Obtain TLS certificate
   # Configure reverse proxy with TLS termination
   ```

3. **Change Default Credentials:**
   ```bash
   # Grafana admin password
   GF_SECURITY_ADMIN_PASSWORD: [strong-password]
   
   # Keycloak admin password
   KEYCLOAK_ADMIN_PASSWORD: [strong-password]
   ```

4. **Rotate Secrets:**
   ```bash
   # Generate new OAuth2-Proxy client secret
   # Update OAUTH2_PROXY_CLIENT_SECRET
   
   # Generate new Grafana client secret
   # Update GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
   ```

5. **Enable Rate Limiting:**
   ```nginx
   # Add to monitoring-router.conf
   limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;
   limit_req zone=auth burst=10 nodelay;
   ```

6. **Restrict Access by IP:**
   ```nginx
   # Allow only internal networks
   allow 192.168.0.0/16;
   deny all;
   ```

### Scalability Configuration

| Setting | Development | Production |
|---------|---|---|
| OAuth2-Proxy Replicas | 1 | 3+ |
| Redis Sessions | Local | Cluster |
| Grafana Replicas | 1 | 3+ |
| Prometheus Retention | 72h | 30d+ |
| Cookie TTL | 1h | 24h |

---

## References

- [OAuth2-Proxy Documentation](https://oauth2-proxy.github.io/)
- [Keycloak OIDC Protocol](https://www.keycloak.org/docs/latest/securing_apps/index.html#_oidc)
- [Grafana OAuth Authentication](https://grafana.com/docs/grafana/latest/auth/generic-oauth/)
- [Prometheus Security](https://prometheus.io/docs/prometheus/latest/configuration/https/)
- [OWASP OAuth 2.0 Security](https://cheatsheetseries.owasp.org/cheatsheets/OAuth_Cheat_Sheet.html)

---

**Last Updated:** March 14, 2026  
**Maintained By:** Platform Security Team  
**Version:** 1.0 - Production Ready
