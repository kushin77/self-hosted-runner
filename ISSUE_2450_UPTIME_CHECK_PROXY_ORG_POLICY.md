# Issue #2450: Cloud Function Proxy Blocked by Organization Policy

## Problem
- Deployed Cloud Function proxy to validate Bearer tokens for uptime checks
- Cloud Function successfully deployed (gen2, Cloud Run service)
- **Blocker**: Organization policy prevents unauthenticated access to Cloud Run services
- HTTP 403 Forbidden returned when attempting to access proxy endpoint
- Affects both Cloud Functions URL and Cloud Run service URL

## Current Status
- ✅ Cloud Function source code created and validated (main.py, requirements.txt)
- ✅ Cloud Function deployed successfully to us-central1 (state: ACTIVE)
- ✅ Function URLs available:
  - `https://us-central1-nexusshield-prod.cloudfunctions.net/uptime-check-proxy`
  - `https://uptime-check-proxy-2tqp6t4txq-uc.a.run.app`
- ❌ Both URLs return HTTP 403 (Forbidden) due to org policy
- ❌ Unable to grant public access via `allUsers` binding
- Error: "One or more users named in the policy do not belong to a permitted customer"

## Root Cause Analysis
Organization policy constraint:
- `constraints/iam.disableServiceAccountKeyCreation` OR
- `constraints/iam.allowedPolicyMemberDomains` OR similar
- Prevents binding `allUsers` or `serviceAccount:*@system.gserviceaccount.com` at the resource level

## Options Considered

### ❌ Option A: Grant Cloud Monitoring System SA Permission
- Attempted to grant `monitoring-notification@system.gserviceaccount.com` invoker role
- Error: Service account does not exist in this organization
- Not a viable path

### ❌ Option B: allUsers IAM Binding
- Attempted: `gcloud functions add-invoker-policy-binding ... --member='allUsers'`
- Error: Org policy blocks this binding
- Requires org policy modification (admin access)

### ✅ Option C: Pragmatic Workaround
**Use direct backend service URLs with IAM-based authentication for uptime checks**
- Instead of proxy, configure uptime checks to call Cloud Run services directly
- Create a service account: `uptime-check-sa@nexusshield-prod.iam.gserviceaccount.com`
- Grant this SA invoker role on both Cloud Run services
- Configure uptime checks to use this SA's credentials (if supported)
- Fallback: Remove proxy and use simpler health check endpoints without Bearer token validation

## Recommended Path Forward

1. **Short-term (Current sprint)**:
   - Remove proxy from uptime check workflow
   - Create public health endpoints on Cloud Run services that don't require authentication
   - Configure uptime checks to call these public endpoints
   - Keep proxy deployed for future use if we can relax org policy

2. **Long-term (Future improvement)**:
   - Request org policy exception for our uptime-check service account
   - Update proxy to accept both Bearer tokens and ID tokens
   - Use service account-based authentication for reliable uptime checks

## Files Involved
- `infra/functions/main.py` - Cloud Function source (deployed, functional)
- `infra/functions/requirements.txt` - Dependencies
- Cloud Functions deployment: `projects/nexusshield-prod/locations/us-central1/functions/uptime-check-proxy`
- Cloud Run service: `projects/nexusshield-prod/locations/us-central1/services/uptime-check-proxy`

## Status
- 🔴 BLOCKED by org policy
- ⏳ Awaiting org policy exception OR
- ⏳ Switching to Option C (public health endpoints)

## Action Items
- [ ] Decide: Wait for org policy exception or switch to public endpoints
- [ ] If switching: Create simple `/health` endpoint on Cloud Run services (no Bearer token req'd)  
- [ ] Update uptime check configs to use new endpoints
- [ ] Validate uptime checks report health status correctly
- [ ] Document the decision in PHASE_4_2_OBSERVABILITY_COMPLETE.md


## Investigation Findings (2026-03-11 04:21 UTC)

### Org Policy Scope
The organization policy `constraints/iam.allowedPolicyMemberDomains` or similar is **global** across all Cloud Run services in nexusshield-prod project:
- ❌ Cloud Function proxy: HTTP 403
- ❌ Cloud Function proxy Cloud Run URL: HTTP 403
- ❌ Backend Cloud Run service `/health`: HTTP 403
- ❌ Frontend Cloud Run service (expected): HTTP 403

**Conclusion**: The org policy is not specifically targeting our proxy, but rather enforcing authentication on all resources that would support `allUsers` binding.

### Recommended Production-Grade Solution

Since Cloud Monitoring uptime checks require public-facing endpoints and org policy blocks unauthenticated access:

1. **Option D: Remove External Uptime Checks** (Current recommendation)
   - Delete/remove the 3 external uptime checks
   - Use internal health checks within the VPC (more secure for private services)
   - Implement synthetic monitoring via Lambda/Cloud Functions within the VPC

2. **Option E: Multi-Cloud Gateway Pattern** (Long-term)
   - Deploy an unauthenticated API gateway (e.g., Cloud Endpoints, App Engine)
   - Gateway validates requests internally and forwards to private Cloud Run services
   - Requires architectural change but provides proper isolation

3. **Option F: Service Account with Identity Tokens** (If uptime checks support it)
   - Cloud Monitoring may support OAuth2 service account authentication
   - Would require investigation of uptime check API capabilities

## Decision
Proceeding with **Option D: Remove External Uptime Checks**
- Simpler, more secure for private services
- Already have internal logging & monitoring (Phase 4.1 complete)
- External uptime checks can be added post-deployment if org policy is relaxed

## Updated Action Items
- [x] Investigate org policy blocking
- [x] Document root cause and constraints
- [ ] **Delete 3 external uptime checks** (nexus-backend-health, nexus-backend-status, nexus-frontend)
- [ ] Verify existing observability stack is sufficient (logging, metrics, dashboards active)
- [ ] Keep Cloud Function proxy deployed (can be used if org policy exception granted)
- [ ] Commit architectural decision to repo

