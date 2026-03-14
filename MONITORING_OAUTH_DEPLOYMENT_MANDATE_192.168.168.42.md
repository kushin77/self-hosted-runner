# 🚨 CRITICAL DEPLOYMENT MANDATE - MONITORING OAUTH STACK

**Date:** March 14, 2026  
**Status:** 🔴 ENFORCEMENT ACTIVE  
**Severity:** CRITICAL

---

## THE MANDATE

| Requirement | Value | Compliance |
|---|---|---|
| **INSTALL MONITORING STACK ON** | `192.168.168.42` | ✅ REQUIRED |
| **DO NOT INSTALL ON** | `192.168.168.31` | ❌ FORBIDDEN |
| **DO NOT USE** | `localhost` (production) | ❌ FORBIDDEN |

---

## IP ADDRESS MAPPING

```
192.168.168.31 = dev-elevatediq-2 (Local Developer Workstation)
                 - This is YOUR LAPTOP
                 - NEVER install services here
                 - Only for development/testing

192.168.168.42 = dev-elevatediq (Production Worker Node)
                 - This is the PRODUCTION TARGET
                 - MUST install everything here
                 - MANDATORY for all deployment scripts

localhost = Your current machine (development only)
           - Works for development on your own computer
           - NOT suitable for production deployment
           - Use only for testing docker-compose locally
```

---

## MONITORING STACK ACCESS ENDPOINTS

### ✅ CORRECT - Production Access (192.168.168.42)

```bash
# Grafana
http://192.168.168.42:4180/grafana/
http://192.168.168.42:3000              (direct, no auth)

# Prometheus
http://192.168.168.42:4180/prometheus/
http://192.168.168.42:9090              (direct, no auth)

# Alertmanager
http://192.168.168.42:4180/alertmanager/
http://192.168.168.42:9093              (direct, no auth)

# Keycloak (OIDC Provider)
http://192.168.168.42:8080/auth/
http://192.168.168.42:8080/auth/admin
```

### ❌ INCORRECT - DO NOT USE

```bash
# These targets are WRONG and services will NOT work:
localhost:4180/grafana/
127.0.0.1:4180/grafana/
192.168.168.31:4180/grafana/            # ← FORBIDDEN (dev laptop)
192.168.168.31:3000
192.168.168.31:8080
```

---

## DEPLOYMENT SCRIPT CONFIGURATION

### Mandatory Environment Variables

```bash
# CORRECT (Production - MANDATORY):
export TARGET_HOST="192.168.168.42"
export WORKER_NODE="192.168.168.42"

# WRONG (Development Workstation - FORBIDDEN):
export TARGET_HOST="192.168.168.31"     # ❌ REJECTED
export WORKER_NODE="192.168.168.31"     # ❌ REJECTED

# DEVELOPMENT ONLY:
export TARGET_HOST="localhost"          # ℹ️ Dev only, requires DEVELOPMENT_MODE=1
export DEVELOPMENT_MODE="1"
```

### Deployment Commands

```bash
# ✅ CORRECT - Deploys to production worker node
bash scripts/setup-monitoring-oauth.sh

# ✅ CORRECT - With explicit target
TARGET_HOST=192.168.168.42 bash scripts/setup-monitoring-oauth.sh

# ❌ WRONG - This will auto-detect and fail
TARGET_HOST=192.168.168.31 bash scripts/setup-monitoring-oauth.sh
# Error: "FATAL ERROR: Deployment to 192.168.168.31 is FORBIDDEN"

# ❌ WRONG - localhost in production mode
TARGET_HOST=localhost bash scripts/setup-monitoring-oauth.sh
# Error: "FATAL ERROR: Deployment to localhost requires DEVELOPMENT_MODE=1"
```

---

## KEYCLOAK OAUTH CLIENT CONFIGURATION

### OAuth2-Proxy Client (PRODUCTION)

```ini
# Configuration for production deployment to 192.168.168.42
CLIENT_ID = oauth2-proxy
ROOT_URL = http://192.168.168.42:4180/
REDIRECT_URI = http://192.168.168.42:4180/oauth2/callback
```

### Grafana Client (PRODUCTION)

```ini
# Configuration for production deployment to 192.168.168.42
CLIENT_ID = grafana
ROOT_URL = http://192.168.168.42:3000/
REDIRECT_URI = http://192.168.168.42:3000/login/generic_oauth
```

### WRONG Configurations

```ini
# ❌ DO NOT USE THESE:
REDIRECT_URI = http://localhost:4180/oauth2/callback        # Development only
REDIRECT_URI = http://192.168.168.31:4180/oauth2/callback   # FORBIDDEN
REDIRECT_URI = http://127.0.0.1:4180/oauth2/callback        # Development only
```

---

## VERIFICATION CHECKLIST

- [ ] Confirm you are deploying TO 192.168.168.42
- [ ] Confirm you are NOT deploying TO 192.168.168.31
- [ ] Confirm all redirect URIs use 192.168.168.42
- [ ] Confirm all environment variables reference 192.168.168.42
- [ ] Confirm logs show "Target: 192.168.168.42" (not .31)
- [ ] Confirm Keycloak clients configured for 192.168.168.42
- [ ] Confirm browser access works to http://192.168.168.42:4180/grafana/

---

## ENFORCEMENT RULES

### Auto-Reject Conditions

The deployment script **WILL IMMEDIATELY STOP** if:

1. `TARGET_HOST` is set to `192.168.168.31`
   ```bash
   Error: "FATAL ERROR: Deployment to 192.168.168.31 is FORBIDDEN"
   ```

2. `TARGET_HOST` is `localhost` without `DEVELOPMENT_MODE=1`
   ```bash
   Error: "FATAL ERROR: Deployment to localhost requires DEVELOPMENT_MODE=1"
   ```

3. Any OAuth redirect URI contains `192.168.168.31`
   ```bash
   Error: "FORBIDDEN: OAuth redirect URI cannot use 192.168.168.31"
   ```

4. Keycloak admin console accessed on developer workstation
   ```bash
   Check: Keycloak admin must be on 192.168.168.42:8080
   ```

---

## TROUBLESHOOTING TARGET ISSUES

### Problem: "Cannot access monitoring stack at....."

```bash
⚠️  Check your URL:
  ❌ http://192.168.168.31:4180/grafana/      (Wrong IP)
  ✅ http://192.168.168.42:4180/grafana/      (Correct IP)

📝 Verify deployment target:
   ssh automation@192.168.168.42 "docker ps | grep oauth2-proxy"
   
   If no containers running:
   → Deployment was not executed on 192.168.168.42
   → Check TARGET_HOST environment variable
```

### Problem: OAuth Redirect Loop

```bash
⚠️  If you see redirect loops:
  1. Check Keycloak client OAuth2-Proxy redirect URIs
     http://192.168.168.42:4180/oauth2/callback  ✅ CORRECT
  
  2. Verify NOT using:
     http://localhost:4180/oauth2/callback        ❌ WRONG
     http://192.168.168.31:4180/oauth2/callback   ❌ WRONG

  3. Update Keycloak clients if needed:
     Client Settings → Valid Redirect URIs
     → Change to http://192.168.168.42:4180/oauth2/callback
```

### Problem: Services Running on Wrong IP

```bash
⚠️  Verify services are bound to 192.168.168.42:
   ssh automation@192.168.168.42 "netstat -tlnp | grep LISTEN"
   
   Expected:
   ✅ 192.168.168.42:4180   (OAuth2-Proxy)
   ✅ 192.168.168.42:3000   (Grafana)
   ✅ 192.168.168.42:9090   (Prometheus)
   
   Wrong:
   ❌ 127.0.0.1:4180        (localhost only - not accessible)
   ❌ 0.0.0.0:4180          (needs explicit IP binding)
```

---

## DOCUMENTATION UPDATES

All files have been updated with mandatory 192.168.168.42 target:

| File | Status | Update |
|---|---|---|
| `MONITORING_OAUTH_ACCESS.md` | ✅ Updated | Enforces 192.168.168.42 for all production URLs |
| `MONITORING_OAUTH_DEPLOYMENT_COMPLETE.md` | ✅ Updated | Emphasizes worker node mandate |
| `KEYCLOAK_OAUTH_CLIENT_SETUP.md` | ✅ Updated | Redirect URIs use 192.168.168.42 |
| `scripts/setup-monitoring-oauth.sh` | ✅ Ready | Auto-rejects wrong targets |
| `scripts/verify-monitoring-oauth.sh` | ✅ Ready | Validates correct target deployment |
| `docker-compose.yml` | ℹ️ Local Dev | Uses localhost for development |

---

## OPERATIONAL REQUIREMENTS

### For Security Team

- ✅ All production deployments MUST target 192.168.168.42
- ✅ Audit logs must show deployment to 192.168.168.42
- ✅ Developer workstations (192.168.168.31) must NOT have services
- ✅ Network isolation prevents .31 from running production workloads

### For DevOps Team

- ✅ SSH keys authorized on 192.168.168.42 only
- ✅ docker-compose deployments run on .42 only
- ✅ Systemd services configured for .42 only
- ✅ Health checks validate .42 endpoints

### For Developers

- ✅ Development testing uses localhost (your machine)
- ✅ Production access uses 192.168.168.42
- ✅ OAuth clients configured for .42 in production
- ✅ Never commit hardcoded .31 references

---

## SIGN-OFF

**This enforcement is ACTIVE and NON-NEGOTIABLE.**

Monitoring OAuth stack MUST be:
- ✅ Deployed to: 192.168.168.42
- ✅ Accessed via: http://192.168.168.42:4180/
- ✅ Configured with Keycloak on: 192.168.168.42:8080
- ✅ NEVER on: 192.168.168.31 (developer workstation)

**Date Enforced:** March 14, 2026  
**Valid Until:** Indefinite (permanent policy)  
**Compliance Level:** MANDATORY
