# Keycloak OAuth2 Client Setup Guide

**Purpose:** Configure Keycloak OIDC clients for OAuth2-Proxy and Grafana  
**Date:** 2026-03-14  
**Target Realm:** `master` (development) or `nexusshield-prod` (production)

---

## 🚨 CRITICAL - DEPLOYMENT TARGET

**Keycloak must be configured to route traffic to the WORKER NODE ONLY:**

| Target | IP Address | Use Case | Status |
|--------|-----------|----------|--------|
| **Production (MANDATE)** | `192.168.168.42` | OAuth2-Proxy client Redirect URI | ✅ REQUIRED |
| **Developer Laptop (FORBIDDEN)** | `192.168.168.31` | DO NOT USE | ❌ REJECTED |
| **Localhost (Dev Only)** | `localhost:4180` | Development testing only | ℹ️ DEV TEST |

**When creating OAuth clients, ALWAYS use `192.168.168.42`, NEVER `192.168.168.31`**

---

## Quick Setup

### 1. Access Keycloak Admin Console

```
Production (MANDATE):  http://192.168.168.42:8080/auth/admin
Development (Laptop):  http://localhost:8080/auth/admin
Username: admin
Password: admin (change in production!)
```

### 2. Create OAuth2-Proxy Client

#### Step 1: Create Client
1. Select Realm: **master**
2. Navigate to: **Clients** → **Create**
3. Fill in:
   - **Client ID:** `oauth2-proxy`
   - **Client Protocol:** `openid-connect`
   - **Root URL:** `http://192.168.168.42:4180/` (WORKER NODE)
   - Click: **Save**

#### Step 2: Configure Client
Under **Settings** tab:
- **Access Type:** `confidential` ✅
- **Standard Flow Enabled:** ✅
- **Implicit Flow Enabled:** ❌
- **Direct Access Grants Enabled:** ✅
- **Service Accounts Enabled:** ✅
- **Valid Redirect URIs:** Add `http://192.168.168.42:4180/oauth2/callback` (WORKER NODE)

#### Step 3: Get Client Secret
1. Go to **Credentials** tab
2. **Client Authenticator:** `Client Id and Secret`
3. Copy the **Secret** value
4. Update docker-compose.yml:
   ```yaml
   OAUTH2_PROXY_CLIENT_SECRET: [paste-secret-here]
   ```

#### Step 4: Configure Client Scopes
1. Go to **Client Scopes** tab
2. Ensure these scopes are assigned:
   - ✅ `openid`
   - ✅ `profile`
   - ✅ `email`

#### Step 5: Verify OIDC Configuration
1. Go to **Installation** tab
2. Select **Keycloak OIDC JSON**
3. You should see (example):
   ```json
   {
     "realm": "master",
     "auth-server-url": "http://localhost:8080/auth",
     "ssl-required": "external",
     "resource": "oauth2-proxy",
     "credentials": {
       "secret": "[client-secret]"
     }
   }
   ```

---

### 3. Create Grafana Client

#### Step 1: Create Client
1. Select Realm: **master**
2. Navigate to: **Clients** → **Create**
3. Fill in:
   - **Client ID:** `grafana`
   - **Client Protocol:** `openid-connect`
   - **Root URL:** `http://192.168.168.42:3000/` (WORKER NODE)
   - Click: **Save**

#### Step 2: Configure Client
Under **Settings** tab:
- **Access Type:** `confidential` ✅
- **Standard Flow Enabled:** ✅
- **Implicit Flow Enabled:** ❌
- **Direct Access Grants Enabled:** ✅
- **Valid Redirect URIs:** Add `http://192.168.168.42:3000/login/generic_oauth` (WORKER NODE)
- **Valid Post Logout Redirect URIs:** Add `http://192.168.168.42:3000/` (WORKER NODE)

#### Step 3: Get Client Secret
1. Go to **Credentials** tab
2. **Client Authenticator:** `Client Id and Secret`
3. Copy the **Secret** value
4. Update docker-compose.yml:
   ```yaml
   GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: [paste-secret-here]
   ```

#### Step 4: Create Client Scope for Groups (Optional)
For group-based access control:

1. Navigate to **Client Scopes** → **Create**
   - **Name:** `groups`
   - **Protocol:** `openid-connect`
   - Click: **Save**

2. Go to **Mappers** → **Create**
   - **Name:** `groups`
   - **Mapper Type:** `Group Membership`
   - **Token Claim Name:** `groups`
   - **Full group path:** ✅
   - Click: **Save**

3. Add to Grafana client scope assignments

#### Step 5: Configure User Mapper for Email
1. Go to Grafana client → **Mappers**
2. Create new mapper:
   - **Name:** `email-mapper`
   - **Mapper Type:** `User Property`
   - **Property:** `email`
   - **Token Claim Name:** `email`
   - Click: **Save**

---

## Create Test Users

### User 1: Admin (Full Access)

1. Navigate to: **Users** → **Add User**
2. Fill in:
   - **Username:** `admin-monitor`
   - **Email:** `admin@example.local`
   - **First Name:** `Admin`
   - **Last Name:** `Monitor`
   - **Email Verified:** ✅
   - **User Enabled:** ✅
   - Click: **Save**

3. Go to **Credentials** tab:
   - Set password: `AdminPass123!`
   - **Temporary:** ❌
   - Click: **Set Password**

4. Go to **Role Mappings**:
   - Assign realm roles:
     - `admin-monitoring`
     - `analytics-admin`

### User 2: Analyst (View-Only Access)

1. Navigate to: **Users** → **Add User**
2. Fill in:
   - **Username:** `analyst-monitor`
   - **Email:** `analyst@example.local`
   - **First Name:** `Analyst`
   - **Last Name:** `Monitor`
   - **Email Verified:** ✅
   - **User Enabled:** ✅
   - Click: **Save**

3. Go to **Credentials** tab:
   - Set password: `AnalystPass123!`
   - **Temporary:** ❌
   - Click: **Set Password**

4. Go to **Role Mappings**:
   - Assign realm roles:
     - `monitoring-viewer`

---

## Create Groups (Optional)

For group-based authorization (requires group mapper in client scope):

### Group 1: Monitoring Admins

1. Navigate to: **Groups** → **New**
2. Fill in:
   - **Name:** `monitoring-admins`
   - Click: **Save**

3. Go to **Role Mappings**:
   - Add roles:
     - `admin-monitoring`
     - `analytics-admin`

4. Add members (drag from Users)

### Group 2: Monitoring Viewers

1. Navigate to: **Groups** → **New**
2. Fill in:
   - **Name:** `monitoring-viewers`
   - Click: **Save**

3. Go to **Role Mappings**:
   - Add roles:
     - `monitoring-viewer`

---

## Create Realm Roles

### Role 1: admin-monitoring

1. Navigate to: **Roles** → **Add Role**
2. Fill in:
   - **Role Name:** `admin-monitoring`
   - **Description:** `Full admin access to monitoring stack`
   - Click: **Save**

### Role 2: monitoring-viewer

1. Navigate to: **Roles** → **Add Role**
2. Fill in:
   - **Role Name:** `monitoring-viewer`
   - **Description:** `View-only access to monitoring dashboards`
   - Click: **Save**

### Role 3: analytics-admin

1. Navigate to: **Roles** → **Add Role**
2. Fill in:
   - **Role Name:** `analytics-admin`
   - **Description:** `Admin access to analytics and reporting`
   - Click: **Save**

---

## Configure Email (Optional)

For email verification and password reset:

1. Navigate to: **Realm Settings** → **Email**
2. Fill in:
   - **Host:** `smtp.example.com`
   - **Port:** `587`
   - **From:** `noreply@example.com`
   - **Username:** `smtp-user`
   - **Password:** `smtp-password`
   - **Enable TLS:** ✅
   - **Enable StartTLS:** ❌
   - Click: **Save**

---

## Configure Realm Settings

### Password Policy

1. Navigate to: **Realm Settings** → **Security Defenses** → **Brute Force Detection**
2. Enable:
   - **Brute Force Detection:** ✅
   - **Max Login Failures:** `5`
   - **Quick Login Check Milliseconds:** `1000`
   - **Minimum Quick Login Wait Seconds:** `60`
   - **Wait Increment Seconds:** `60`

### Token Expiration

1. Navigate to: **Realm Settings** → **Tokens**
2. Set:
   - **Access Token Lifespan:** `12 hours`
   - **Client Session Idle Timeout:** `30 minutes`
   - **Client Session Max Lifespan:** `4 hours`
   - **Offline Session Idle Timeout:** `7 days`

---

## Verification Steps

### 1. Test OAuth2-Proxy Authentication

```bash
# Navigate to OAuth2-Proxy flow
# This should redirect to Keycloak login:
curl -L -i http://localhost:4180/oauth2/auth \
  -H "X-Forwarded-For: 127.0.0.1"

# Expected: 302 redirect to Keycloak
# Location: http://keycloak:8080/auth/realms/master/protocol/openid-connect/auth?...
```

### 2. Test Grafana OIDC Authentication

```bash
# Visit Grafana OAuth login page
curl -i http://localhost:3000/login/generic_oauth

# Expected: 302 redirect to Keycloak authorization endpoint
```

### 3. Test in Browser

1. Open: `http://localhost:4180/grafana/`
2. Should redirect to: `http://localhost:8080/auth/realms/master/protocol/...`
3. Login with test user credentials (e.g., `admin-monitor`)
4. Accept consent (if first time)
5. Redirected back to Grafana dashboard

### 4. Verify OIDC Discovery

```bash
# Check Keycloak OIDC configuration
curl http://localhost:8080/auth/realms/master/.well-known/openid-configuration

# Should return JSON with:
# - token_endpoint
# - authorization_endpoint
# - userinfo_endpoint
# - jwks_uri
```

---

## Troubleshooting

### Issue: "Invalid client ID" in OAuth2-Proxy logs

```bash
# 1. Verify client exists in Keycloak
curl http://localhost:8080/auth/admin/realms/master/clients
# Filter for "oauth2-proxy" client

# 2. If missing, create client again via admin console

# 3. Verify secret matches in docker-compose.yml
# 4. Restart OAuth2-Proxy
docker-compose restart oauth2-proxy
```

### Issue: "Invalid redirect URI" during login

```bash
# 1. Check configured redirect URIs in Keycloak
# Navigate to: Clients → oauth2-proxy → Settings
# Verify "Valid Redirect URIs" includes:
#   http://localhost:4180/oauth2/callback

# 2. If missing, add the URI and save

# 3. Test again
```

### Issue: "User not found" in Grafana after OIDC login

```bash
# 1. Verify user exists in Keycloak
# Keycloak: Users → Check user email

# 2. Verify email mapper configured
# Keycloak: Grafana client → Mappers
# Should have "email" mapper (see "Configure User Mapper" above)

# 3. Restart Grafana to apply mapper changes
docker-compose restart grafana
```

### Issue: Empty user groups in Grafana

```bash
# 1. Verify groups client scope configured
# Keycloak: Client Scopes → groups scope

# 2. Verify mapper exists
# Keycloak: Client Scopes → groups → Mappers
# Should have "groups" mapper of type "Group Membership"

# 3. Verify user assigned to groups
# Keycloak: Users → [user] → Groups
# Check group membership

# 4. Restart Grafana
docker-compose restart grafana
```

---

## Security Best Practices

### Development

- ✅ Use HTTP for testing
- ✅ Allow unverified email
- ✅ Skip PKCE verification
- ❌ Don't use default passwords in production
- ✅ Document test credentials

### Production

- ✅ Use HTTPS with TLS
- ✅ Require email verification
- ✅ Enable PKCE
- ✅ Use strong client secrets (32+ characters)
- ✅ Rotate secrets quarterly
- ✅ Enable brute force protection
- ✅ Set strict password policies
- ✅ Audit user access regularly
- ✅ Use separate realms for dev/prod
- ✅ Enable rate limiting

---

## References

- [Keycloak Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Keycloak OIDC Protocol](https://www.keycloak.org/docs/latest/securing_apps/#openid-connect)
- [OAuth2-Proxy OIDC Configuration](https://oauth2-proxy.github.io/oauth2-proxy/docs/configuration/oauth_provider/#oidc-provider)
- [Grafana OAuth2 Authentication](https://grafana.com/docs/grafana/latest/auth/generic-oauth/)

---

**Maintained By:** Platform Security Team  
**Last Updated:** March 14, 2026  
**Status:** ✅ Production Ready
