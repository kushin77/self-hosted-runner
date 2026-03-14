# Google OAuth Setup Guide - Grafana Monitoring Stack
**Date:** 2026-03-14  
**Status:** Ready for Configuration  
**Target:** Grafana & OAuth2-Proxy (192.168.168.42:3000, 192.168.168.42:4180)

---

## STEP 1: Get Google OAuth Credentials

### 1.1 Create a Google Cloud Project
1. Visit: https://console.cloud.google.com
2. Create new project: "Nexus Shield Monitoring"
3. Enable Google+ API:
   - Click "APIs & Services" → "Library"
   - Search for "Google+ API"
   - Click "Enable"

### 1.2 Create OAuth 2.0 Credentials
1. Go to "APIs & Services" → "Credentials"
2. Click "Create Credentials" → "OAuth client ID"
3. Select "Web application"
4. **Fill in:**
   - **Name:** Grafana Monitoring OAuth
   - **Authorized JavaScript origins:**
     ```
     http://192.168.168.42:3000
     http://192.168.168.42:4180
     http://localhost:3000
     http://localhost:4180
     ```
   - **Authorized redirect URIs:**
     ```
     http://192.168.168.42:3000/login/google
     http://192.168.168.42:4180/oauth2/callback
     http://localhost:3000/login/google
     http://localhost:4180/oauth2/callback
     ```
5. Click "Create"
6. **Copy these values:**
   - **Client ID:** `xxxxx.apps.googleusercontent.com`
   - **Client Secret:** `xxxxxxxxxxxxxxxx`

---

## STEP 2: Configure Environment Variables

### Option A: Using .env File (Recommended)
Create `.env` file in `/home/akushnir/self-hosted-runner/`:
```bash
# Google OAuth Credentials
GOOGLE_OAUTH_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=YOUR_CLIENT_SECRET
```

### Option B: Export in Terminal
```bash
export GOOGLE_OAUTH_CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com"
export GOOGLE_OAUTH_CLIENT_SECRET="YOUR_CLIENT_SECRET"
docker-compose up -d
```

### Option C: Update docker-compose.yml Directly
Replace `${GOOGLE_OAUTH_CLIENT_ID:-...}` with actual values in docker-compose.yml:
```yaml
GF_AUTH_GOOGLE_CLIENT_ID: "YOUR_CLIENT_ID.apps.googleusercontent.com"
GF_AUTH_GOOGLE_CLIENT_SECRET: "YOUR_CLIENT_SECRET"
OAUTH2_PROXY_CLIENT_ID: "YOUR_CLIENT_ID.apps.googleusercontent.com"
OAUTH2_PROXY_CLIENT_SECRET: "YOUR_CLIENT_SECRET"
```

---

## STEP 3: Deploy with Google OAuth

### Deploy Grafana & OAuth2-Proxy
```bash
cd /home/akushnir/self-hosted-runner

# Option A: With .env file
docker-compose up -d grafana oauth2-proxy monitoring-router

# Option B: With environment variables
GOOGLE_OAUTH_CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com" \
GOOGLE_OAUTH_CLIENT_SECRET="YOUR_CLIENT_SECRET" \
docker-compose up -d grafana oauth2-proxy monitoring-router
```

### Verify Services Started
```bash
docker-compose ps | grep -E 'grafana|oauth2-proxy'
# Expected: both should be "Up"
```

### Check Logs
```bash
docker-compose logs -f grafana
# Should show: GF_AUTH_GOOGLE_ENABLED = true

docker-compose logs -f oauth2-proxy
# Should show: provider = google
```

---

## STEP 4: Test Google OAuth Login

### Test Google Login URL
```bash
# Visit OAuth login page
open http://192.168.168.42:4180/login
# or
curl -I http://192.168.168.42:4180/login
```

**Expected flow:**
1. User visits http://192.168.168.42:3000
2. Redirected to OAuth2-Proxy login
3. OAuth2-Proxy redirects to Google login
4. User logs in with Google account
5. Google redirects back to http://192.168.168.42:4180/oauth2/callback
6. OAuth2-Proxy validates token
7. User authenticated, access to Grafana ✅

### Verify No Local Auth
```bash
# Try to access Grafana directly (should fail without OAuth)
curl -v http://192.168.168.42:3000/
# Expected: 401 or redirect to OAuth

# Try with OAuth token (should work)
curl -v http://192.168.168.42:4180/grafana/ \
  -H "Authorization: Bearer <GOOGLE_TOKEN>"
# Expected: 200 OK
```

---

## STEP 5: Troubleshooting

### Issue 1: "Invalid Client ID" Error
**Cause:** Client ID/Secret incorrect or not set
**Fix:**
```bash
# Verify environment variables are set
env | grep GOOGLE_OAUTH

# Check docker-compose has correct values
docker-compose config | grep GOOGLE_OAUTH_CLIENT

# Verify in Google Cloud Console the Client ID hasn't changed
```

### Issue 2: "Redirect URI Mismatch"
**Cause:** Redirect URL not in Google OAuth authorized list
**Fix:**
1. Visit Google Cloud Console → Credentials
2. Click on OAuth 2.0 Client ID
3. Add http://192.168.168.42:3000/login/google
4. Add http://192.168.168.42:4180/oauth2/callback
5. Click Save

### Issue 3: "Invalid Scope" or "Access Denied"
**Cause:** Google account doesn't have permission
**Fix:**
1. Try with a different Google account used for development
2. Ensure account has no restrictive organization policies
3. Check Google+ API is enabled in Cloud Console

### Issue 4: User Landing on Login Form Still
**Cause:** GF_AUTH_DISABLE_LOGIN_FORM not applied or Grafana needs restart
**Fix:**
```bash
docker-compose restart grafana
docker-compose logs grafana | grep GF_AUTH_GOOGLE
# Should show: GF_AUTH_GOOGLE_ENABLED = true
```

---

## STEP 6: Verify Google OAuth is Exclusive

### Test 1: No Local Login Available
```bash
# Visit Grafana
curl http://192.168.168.42:3000/
# Should redirect to OAuth, NOT show login form
# Should NOT have username/password fields
```

### Test 2: OAuth2-Proxy Validates All Access
```bash
# Direct access without OAuth token
curl http://192.168.168.42:4180/prometheus/
# Expected: 401 Unauthorized (X-Auth header missing)

# With Google OAuth token
curl http://192.168.168.42:4180/prometheus/ \
  -H "Authorization: Bearer <GOOGLE_TOKEN>"
# Expected: 200 OK (forwarded to Prometheus)
```

### Test 3: Google Account Provisioning
```bash
# Log in with Google account
# Check Grafana Admin → Users
# Your Google email should be auto-created as Viewer
```

---

## CONFIGURATION REFERENCE

### Grafana Google OAuth Settings
| Setting | Value |
|---------|-------|
| Provider | Google |
| Client ID | YOUR_CLIENT_ID.apps.googleusercontent.com |
| Client Secret | YOUR_CLIENT_SECRET |
| Scopes | openid profile email |
| Auth URL | https://accounts.google.com/o/oauth2/v2/auth |
| Token URL | https://oauth2.googleapis.com/token |
| User Info URL | https://openidconnect.googleapis.com/v1/userinfo |
| Redirect URL | http://192.168.168.42:3000/login/google |
| Auto Login | enabled |
| Auto Sign Up | enabled |
| Default Role | Viewer |

### OAuth2-Proxy Google Settings
| Setting | Value |
|---------|-------|
| Provider | google |
| Client ID | YOUR_CLIENT_ID.apps.googleusercontent.com |
| Client Secret | YOUR_CLIENT_SECRET |
| Redirect URL | http://192.168.168.42:4180/oauth2/callback |
| Email Domains | * (all Google accounts) |
| Validate URL | https://www.googleapis.com/oauth2/v2/userinfo |
| Cookie Duration | 3600 seconds (1 hour) |

---

## SECURITY NOTES

### ✅ What's Secured
- All credentials stored in environment variables (never in code)
- Google OAuth validates every request (strict enforcement)
- Cookies are HttpOnly + SameSite (CSRF protected)
- No local authentication possible (Google ONLY)
- All monitoring services OAuth-protected

### ❌ Avoid
- Hardcoding credentials in docker-compose.yml
- Committing Client Secret to git
- Using overly permissive redirect URIs
- Allowing unauthenticated access to any endpoint

### ✅ Best Practices
- Store Client Secret in GSM/Vault (production)
- Rotate Client Secret quarterly
- Use specific redirect URIs (not wildcards)
- Enable Security Best Practices in Google Cloud Console
- Audit OAuth access logs regularly

---

## NEXT STEPS

### Immediate
1. [ ] Create Google Cloud Project
2. [ ] Generate OAuth credentials
3. [ ] Set environment variables
4. [ ] Deploy docker-compose
5. [ ] Test Google OAuth login

### Verify
1. [ ] Grafana login redirects to Google
2. [ ] No local login form visible
3. [ ] Google account auto-provisioned in Grafana
4. [ ] OAuth2-Proxy validates all access
5. [ ] Prometheus/Alertmanager/metrics OAuth-protected

### Production
1. [ ] Store credentials in GSM/Vault
2. [ ] Update redirect URIs for production domain
3. [ ] Enable Security Best Practices
4. [ ] Set up audit logging
5. [ ] Test with real Google accounts

---

## ROLLBACK (If Needed)

### Switch Back to Keycloak
```bash
# Restore docker-compose.yml from git
git checkout docker-compose.yml

# Remove .env file if created
rm .env

# Redeploy
docker-compose down grafana oauth2-proxy monitoring-router
docker-compose up -d grafana oauth2-proxy monitoring-router
```

### Verify Keycloak OAuth
```bash
docker-compose logs grafana | grep GF_AUTH_GENERIC_OAUTH
# Should show Keycloak configuration
```

---

**Setup Guide:** Completed  
**Status:** Ready for Google OAuth Configuration  
**Support:** See OPERATOR_HANDOFF_STATUS_20260314.md for additional help

Signed: GitHub Copilot  
Date: 2026-03-14T19:15:00Z
