# Operations Handoff — Milestone 4 (2026-03-12)

## Quick Start for Operations Team

### Health Check (Always Safe)
```bash
# From devhost or via SSH to fullstack (192.168.168.42):
curl -sS http://localhost:8080/health      # Backend API
curl -sS http://localhost:13000/           # Frontend portal
docker ps | grep -E "backend|postgres|frontend|redis"
```

### If Services are Down (Restart Procedure)
```bash
# SSH to fullstack
ssh akushnir@192.168.168.42

# Check if idle-cleanup timer is enabled (should not be)
systemctl status idle-cleanup.timer

# Disable if running
sudo systemctl disable idle-cleanup.timer
sudo systemctl stop idle-cleanup.timer

# Restart services
docker-compose -f /home/akushnir/self-hosted-runner/docker-compose.yml restart

# Tail logs
docker logs -f nexusshield-backend
```

### Key Port Mappings
| Port | Service | Health Endpoint |
|---|---|---|
| **8080** | Backend API | `curl http://localhost:8080/health` |
| **13000** | Frontend | `curl http://localhost:13000/` (React app) |
| 5432 | PostgreSQL | (internal, no HTTP) |
| 6379 | Redis | (internal, no HTTP) |

---

## Automated Daily Maintenance

**All running via systemd timers (no manual action needed):**

| Timer | Schedule | Purpose | Location |
|---|---|---|---|
| `credential-rotation-gsm.timer` | 3 AM daily | Rotate deployment credentials | `/scripts/rotate-deploy-credentials.sh` |
| `credential-rotation-vault.timer` | 3 AM daily (if Vault enabled) | Vault secret sync | Phase 5 feature |
| `compliance-audit.timer` | 4 AM daily | Audit logging, immutability verification | `/scripts/compliance-audit.sh` |

**Status check:**
```bash
systemctl list-timers --all | grep -E "credential|compliance|audit"
```

---

## Credential Management

### Where Credentials Are Stored
- **Primary:** Google Secret Manager (GSM) — `nexusshield-prod` project
- **Fallback:** HashiCorp Vault (Phase 5, requires VAULT_ADDR)
- **2nd Fallback:** AWS KMS (Phase 5, requires AWS account setup)

### Credential Rotation
- Automatic: runs daily 3 AM via systemd timer
- Manual trigger:
  ```bash
  bash /home/akushnir/self-hosted-runner/scripts/rotate-deploy-credentials.sh
  ```

### Deployer Service Account
- **Account:** `prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com`
- **Auth Method:** Workload Identity Federation (OIDC)
- **Scope:** Limited to repository `kushin77/self-hosted-runner` (attribute condition enforced)

---

## Deployment Process

### How Deployments Happen (No PRs, No GitHub Actions)
1. Developer commits code directly to `main`
2. Pre-commit hooks run (credential detection, code quality)
3. Git commit succeeds → immutable JSONL audit log written
4. Docker containers restart (assuming compose file updated)
5. Health checks performed automatically
6. Audit trail committed back to main

### Making a Change
```bash
# On local dev machine or via direct host access:
cd /home/akushnir/self-hosted-runner

# Make code/config changes
# (e.g., update docker-compose.yml, backend code, frontend assets)

# Commit directly to main
git add .
git commit -m "feat: your change description"
git push origin main

# Docker-compose will automatically pull latest and restart
# (if running in watch mode or cron job triggers it)
```

### Immutable Audit Trail
- Every deployment creates a JSONL log in `/deployments/audit_*.jsonl`
- Every change is committed to git with full commit hash
- Impossible to alter past deployments (write-once logs)

---

## Troubleshooting

### Backend API Not Responding (500 errors)
```bash
# Check logs
docker logs --tail=50 nexusshield-backend

# Look for common issues:
# - Database connection refused → check Postgres is running
# - Missing env vars → check GSM credentials loaded
# - Port conflict → check no other service on 8080

# Restart backend only
docker restart nexusshield-backend
```

### Database Connection Issues
```bash
# Verify Postgres is running
docker ps | grep postgres

# Check logs
docker logs nexusshield-postgres | tail -20

# Verify port is open
ss -tln | grep 5432

# Restart database
docker restart nexusshield-postgres
# ⚠️ Will interrupt all connections; ensure no active queries
```

### Frontend Not Loading
```bash
# Check React app container
docker logs nexusshield-frontend

# Verify port 13000
curl -I http://localhost:13000/

# Restart frontend
docker restart nexusshield-frontend
```

### Idle-Cleanup Stopping Containers (Unwanted)
```bash
# Disable the timer permanently
sudo systemctl disable idle-cleanup.timer
sudo systemctl stop idle-cleanup.timer

# Remove the unit files
sudo rm -f /etc/systemd/system/idle-cleanup.service
sudo rm -f /etc/systemd/system/idle-cleanup.timer
sudo systemctl daemon-reload

# Verify disabled
sudo systemctl status idle-cleanup.timer
# Expected: "Unit idle-cleanup.timer could not be found"
```

---

## Monthly Operations Tasks

### 1st Friday of Month — GitHub Actions Compliance
**Verify no GitHub Actions workflows exist:**
```bash
find .github/workflows -name "*.yml" -o -name "*.yaml" | wc -l
# Should output: 0
```

### 3rd Friday of Month — Audit Trail Compliance
**Verify JSONL audit logs:**
```bash
ls -la /home/akushnir/self-hosted-runner/deployments/audit_*.jsonl | wc -l
# Should show recent audit files

# Verify checksums
sha256sum -c /home/akushnir/self-hosted-runner/logs/checksums.sha256
```

### Mid-Month — Credential Rotation Verification
**Verify credentials were rotated:**
```bash
# Check GSM for recent secret versions
gcloud secrets versions list prod-deployer-key --limit=5 --project=nexusshield-prod

# Check rotation logs
journalctl -u credential-rotation-gsm.service --since="7 days ago" | tail -10
```

---

## Escalation & Support

### If Systems Are Down
1. **Check health:** `curl -sS http://localhost:8080/health`
2. **Restart services:** See "If Services are Down" section above
3. **Check logs:** `docker logs -f nexusshield-backend` and systemd timers
4. **Contact:** Lead Engineer (full diagnostic logs and git revision history available)

### For Vault Integration (Phase 5)
- Contact: Ops team to provide `VAULT_ADDR` and Vault admin access
- See: `issues/0001-REQUEST-VAULT-ADDR-AND-ADMIN-TOKEN.md`
- Timeline: Estimated Phase 5, non-blocking for current production

### For Multi-Cloud Failover (Phase 5+)
- Requires AWS account setup and KMS key provisioning
- Contingent on Phase 5 completion of Vault integration

---

## Documentation References

| Document | Purpose | Location |
|---|---|---|
| Remediation Report | Idle-cleanup fixes, service restart history | [MILESTONE_4_COMPLETION_REMEDIATION_20260312.md](MILESTONE_4_COMPLETION_REMEDIATION_20260312.md) |
| Final Sign-Off | Milestone 4 completion checklist | [MILESTONE_4_FINAL_SIGN_OFF_20260312.md](MILESTONE_4_FINAL_SIGN_OFF_20260312.md) |
| Runbook - API Health | Step-by-step operator procedures | [issues/ISSUE-REMEDIATE-API-HEALTH.md](issues/ISSUE-REMEDIATE-API-HEALTH.md) |
| Health Validation | Automated health check script | [scripts/final-health-validation.sh](scripts/final-health-validation.sh) |
| Vault Setup | Phase 5 Vault integration (future) | [issues/0001-REQUEST-VAULT-ADDR-AND-ADMIN-TOKEN.md](issues/0001-REQUEST-VAULT-ADDR-AND-ADMIN-TOKEN.md) |

---

## Key Contacts & Permissions

- **Lead Engineer:** @akushnir
- **Production Host:** `192.168.168.42` (fullstack)
- **GCP Project:** `nexusshield-prod`
- **Git Repo:** `kushin77/self-hosted-runner@main`

### Required Access
- [ ] SSH to fullstack (192.168.168.42)
- [ ] Docker access on fullstack
- [ ] GCP Secret Manager read access
- [ ] Git commit access to main branch

---

## Post-Milestone 4 Roadmap

### Phase 5 — Multi-Cloud Vault & Advanced Credentials (Operator-Initiated)
- Vault AppRole setup (requires operator to provide Vault HTTPS URL)
- GSM → Vault secret replication
- AWS KMS integration (requires AWS account)

### Phase 7+ — Enterprise Scale-Out
- Multi-region deployment
- Load balancing
- Disaster recovery procedures
- Advanced observability (Datadog/ELK integration)

---

## Service Level Commitments

| SLA | Target | Current Status |
|---|---|---|
| API Uptime | 99.9% | ✅ 100% (24+ hours since Milestone 4 completion) |
| Deployment Time | < 5 minutes | ✅ ~2-3 minutes (docker-compose) |
| Credential Rotation | Daily | ✅ Automated 3 AM daily |
| Audit Trail Retention | 90 days | ✅ Immutable JSONL + git history |

---

**Handoff Date:** 2026-03-12  
**Prepared By:** Lead Engineer (@akushnir)  
**Status:** PRODUCTION READY  
**Operations Team:** Ready to take over routine maintenance
