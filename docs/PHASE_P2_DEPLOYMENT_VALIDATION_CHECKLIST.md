# Phase P2 Production Deployment Validation Checklist

**Date**: March 5, 2026  
**Deployment Engineer**: ________________  
**Environment**: Production  
**Approval**: ________________  

---

## Pre-Deployment Verification

- [ ] **Code Review Complete**
  - All Phase P2 PRs merged to main (#61, #77, #88, #124, #130, #133, #142, #143)
  - No outstanding breaking issues in main branch

- [ ] **Credentials & Access**
  - Vault AppRole credentials generated and stored securely
  - Docker registry credentials configured
  - GitHub personal access token available (for runner registration)
  - AWS/cloud credentials for infrastructure (if needed)

- [ ] **Infrastructure Ready**
  - Redis instance provisioned and tested for connectivity
  - Terraform state backend configured (S3, Consul, or local)
  - Network access verified between deployment host and Vault/Redis
  - DNS resolution working for all external services

- [ ] **Documentation Review**
  - [docs/PROVISIONER_WORKER_PROD_ROLLOUT.md](../docs/PROVISIONER_WORKER_PROD_ROLLOUT.md) - Read and understood
  - [docs/VAULT_PROD_SETUP.md](../docs/VAULT_PROD_SETUP.md) - AppRole configured
  - [docs/PHASE_P2_DELIVERY_SUMMARY.md](../docs/PHASE_P2_DELIVERY_SUMMARY.md) - Architecture reviewed

---

## Stage 1: Container Image Build

- [ ] **Docker Build**
  ```bash
  docker build -t self-hosted-runner:prod-p2 \
    -f build/github-runner/Dockerfile \
    --build-arg NODE_ENV=production \
    .
  ```
  - Build completes without errors
  - Image size reasonable (< 500MB expected)
  - Labels applied correctly (git.commit, build.date)

- [ ] **Image Verification**
  ```bash
  docker run --rm self-hosted-runner:prod-p2 node --version
  docker run --rm self-hosted-runner:prod-p2 npm ls 2>/dev/null | head -20
  ```
  - Node.js version matches expected (18.x or later)
  - All dependencies present

- [ ] **Registry Push** (if using private registry)
  ```bash
  docker tag self-hosted-runner:prod-p2 <registry>/provisioner-worker:prod-p2
  docker push <registry>/provisioner-worker:prod-p2
  ```
  - Push succeeds and completes
  - Image accessible from deployment host

---

## Stage 2: Environment Configuration

- [ ] **Vault Setup**
  - [ ] AppRole created: `auth/approle/role/provisioner-worker`
  - [ ] Policy attached: `provisioner-worker`
  - [ ] Role ID confirmed: `echo $VAULT_ROLE_ID`
  - [ ] Secret ID generated: `echo $VAULT_SECRET_ID | wc -c` (should be 32+ chars)
  - [ ] Token TTL acceptable (1-4 hours recommended for production)

- [ ] **Redis Configuration**
  - [ ] Connectivity verified: `redis-cli -h <host> ping` → PONG
  - [ ] Persistence enabled (RDB or AOF if applicable)
  - [ ] Memory limit set appropriately
  - [ ] Auth password set (if not localhost)
  - [ ] URL format correct: `redis://[user:password@]host:port/db`

- [ ] **Environment Variables Set**
  ```bash
  export USE_TERRAFORM_CLI=1
  export PROVISIONER_REDIS_URL=redis://...
  export VAULT_ADDR=https://vault.example.com
  export VAULT_ROLE_ID=<role-id>
  export VAULT_SECRET_ID=<secret-id>
  export VAULT_SKIP_VERIFY=true  # Only for dev; use proper certs in prod
  ```

---

## Stage 3: Service Deployment

### Docker Deployment

- [ ] **docker-compose Up**
  ```bash
  docker-compose \
    -f services/provisioner-worker/deploy/docker-compose.yml \
    up -d
  ```
  - All services start cleanly
  - No container exits abnormally
  - Verify: `docker-compose ps` shows all containers running

- [ ] **Service Logs Clean**
  ```bash
  docker-compose logs -f provisioner-worker | head -50
  ```
  - No ERROR or FATAL messages in first 30 lines
  - Worker loop logging visible: "Worker started"
  - No connection failures to Vault or Redis

### Systemd Deployment (Alternative)

- [ ] **Service Unit Installed**
  ```bash
  sudo ls -la /etc/systemd/system/provisioner-worker.service
  ```
  - File exists and is readable

- [ ] **Service Started & Enabled**
  ```bash
  sudo systemctl daemon-reload
  sudo systemctl enable provisioner-worker
  sudo systemctl start provisioner-worker
  sudo systemctl status provisioner-worker
  ```
  - Service shows "active (running)"
  - No errors in status output

- [ ] **Service Logs Clean**
  ```bash
  sudo journalctl -u provisioner-worker -n 50 -f
  ```
  - No ERROR or connection failure messages
  - Periodic status logs showing worker polling

---

## Stage 4: Vault & Secret Access Validation

- [ ] **AppRole Authentication**
  ```bash
  vault write -field=client_token auth/approle/login \
    role_id=$VAULT_ROLE_ID \
    secret_id=$VAULT_SECRET_ID
  ```
  - Returns a valid token
  - Token can be used to authenticate subsequent requests

- [ ] **Secret Read Test**
  ```bash
  vault kv get secret/provisioner-worker/test
  ```
  - Can read test secret with provisioner-worker credentials
  - Response includes expected fields

- [ ] **Token Refresh**
  - [ ] Token TTL displayed: `vault token lookup`
  - [ ] Refresh mechanism working (if applicable)
  - [ ] No immediate token expiration warnings

---

## Stage 5: Provisioner-Worker Smoke Test

- [ ] **Enqueue Test Job**
  ```bash
  curl -X POST http://localhost:5000/provision \
    -H "Content-Type: application/json" \
    -d '{
      "request_id": "test-smoke-001",
      "workspace": "test-runner-smoke-001",
      "tfVariables": { "github_org": "test-org" },
      "tfFiles": "null_resource { id = \"provisioner-test\" }"
    }'
  ```
  - Response: 202 Accepted (or 200 OK)
  - Job appears in queue

- [ ] **Verify Job Processing**
  ```bash
  watch -n 1 'redis-cli HGETALL provisioning:jobs | tail -20'
  ```
  - Job status transitions: queued → processing → provisioned
  - Processing completes within 30 seconds
  - No errors in status payload

- [ ] **Verify jobStore Persistence** (if file-backed)
  ```bash
  ls -la services/provisioner-worker/data/jobstore.json
  ```
  - File created after first job
  - Size increases as jobs complete
  - Can read and validate JSON structure

- [ ] **Verify Terraform Workspace Created**
  ```bash
  ls -la services/provisioner-worker/workspaces/test-smoke-001/
  docker exec provisioner-worker-1 terraform -v  # Inside container
  ```
  - Workspace directory exists
  - Contains Terraform files and state

---

## Stage 6: Real Usage Test (Optional)

- [ ] **Register Real Runner** (if authorizations in place)
  ```bash
  curl -X POST http://localhost:5000/provision \
    -H "Content-Type: application/json" \
    -d '{
      "request_id": "real-runner-prod-001",
      "workspace": "prod-runner-001",
      "tfVariables": {
        "github_org": "myorg",
        "runner_group": "default",
        "instance_type": "t3.medium"
      },
      "tfFiles": "..."
    }'
  ```
  - Job queued successfully
  - Terraform plan/apply completes
  - Runner becomes visible in GitHub Actions → Settings → Runners

---

## Stage 7: Monitoring & Observability

- [ ] **Log Aggregation**
  - [ ] provisioner-worker logs flowing to log aggregation system
  - [ ] managed-auth logs visible
  - [ ] No application errors in aggregation dashboard

- [ ] **Metrics Export** (Phase P3 preparation)
  - [ ] `/metrics` endpoint available: `curl http://localhost:9090/metrics`
  - [ ] Documentation for Prometheus scrape config prepared

- [ ] **Alert Rules Ready** (Phase P3 preparation)
  - [ ] Alert rule definitions prepared and reviewed
  - [ ] Alertmanager routing configured
  - [ ] Test alert can be triggered manually

---

## Stage 8: Operational Readiness

- [ ] **Service Restart Behavior**
  ```bash
  docker-compose restart provisioner-worker
  # OR
  sudo systemctl restart provisioner-worker
  ```
  - Service restarts cleanly
  - Resumes job processing without manual intervention
  - Redis queue state preserved

- [ ] **Emergency Procedures Documented**
  - [ ] Runbook for restarting services
  - [ ] Runbook for draining job queue
  - [ ] Runbook for emergency scale-up/scale-down
  - [ ] Escalation contacts identified

- [ ] **On-Call Setup**
  - [ ] Runbook accessible to on-call team
  - [ ] Access credentials stored securely
  - [ ] Slack/PagerDuty notifications configured
  - [ ] Duty handoff process documented

---

## Stage 9: Production Stability Window

- [ ] **Monitoring Duration: 1+ Hour**
  - Every 10 minutes: Check service health
    ```bash
    docker-compose ps  # or systemctl status
    ```
  - Every 5 minutes: Check logs for errors
    ```bash
    docker-compose logs --tail=20 provisioner-worker | grep -i error
    ```
  - No restarts, crashes, or manual interventions required

- [ ] **Load Test** (Optional, if capacity testing available)
  - Enqueue 10+ jobs simultaneously
  - Observe queue processing rate
  - Monitor CPU/memory utilization
  - Document observed throughput (jobs/min)

- [ ] **Zero-Downtime Observations**
  - No dropped jobs
  - No duplicate provisioning detected
  - No race conditions or lock contention

---

## Stage 10: Sign-Off & Documentation

- [ ] **Deployment Summary Updated**
  - Actual image digest recorded
  - Deployment timestamp captured
  - Team member names and sign-offs documented

- [ ] **Known Issues Logged** (if any)
  - Open issue for any observed warnings
  - Severity and urgency assessed
  - Assigned to backlog or Phase P3/P4

- [ ] **Issue #147 (Execution) Closed**
  ```
  Summary:
  - Image built and pushed: <digest>
  - Services deployed to: <environment>
  - Validation completed: <timestamp>
  - Status: ✅ Production Ready
  ```

- [ ] **Handoff to On-Call**
  - Runbook provided
  - Training session scheduled (optional)
  - Contact info for escalations confirmed

---

## Rollback Plan (If Needed)

If any stage fails or production issues arise after deployment:

1. **Immediate Rollback** (< 5 minutes)
   ```bash
   # Disable Terraform CLI provisioning
   export USE_TERRAFORM_CLI=0
   docker-compose restart provisioner-worker
   # OR
   sudo systemctl restart provisioner-worker
   ```
   Services revert to stub runner; no real provisioning occurs.

2. **Full Rollback** (< 15 minutes)
   - Keep staging environment running in parallel
   - Point traffic/API calls back to staging
   - Investigate issues in production environment (no hurry)
   - Schedule new deployment attempt after fixes

3. **Post-Incident Review**
   - Document root cause
   - Update runbooks
   - Plan remediation (Phase P3/P4 enhancement)

---

## Success Criteria

**All stages complete with:**
- ✅ No ERROR or FATAL log messages
- ✅ Service restarts stable and predictable
- ✅ At least 1 successful provisioning job end-to-end
- ✅ 1+ hour stable operation without intervention
- ✅ On-call team trained and ready
- ✅ Runbooks accessible and up-to-date

---

**Deployment Time Estimate**: 2-3 hours (including validation)  
**Approval Date**: ________________  
**Approved By**: ________________  
**Deployment Completed**: ________________  

