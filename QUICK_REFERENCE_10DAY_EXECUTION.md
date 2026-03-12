# 📄 QUICK REFERENCE: 10-DAY EXECUTION CARD

**Printed For**: Team Daily Standup (9 AM UTC)  
**Go-Live**: March 22, 2026 (10 days)  

---

## 🎯 CRITICAL PATH (P0 Items — Blocking Go-Live)

```
┌─────────────────────────────────────────────────────────────────┐
│ DAY 1 (Mar 13)   → API Unification Layer                         │
│ ✓ Unified response schema (all endpoints)                        │
│ ✓ SDK generation (TypeScript, Python, Go)                       │
│ ✓ Error code standardization                                    │
├─────────────────────────────────────────────────────────────────┤
│ DAY 2 (Mar 14)   → Immutability + Redundancy                    │
│ ✓ Audit events table (append-only)                              │
│ ✓ Cloud SQL replica (us-west1)                                  │
│ ✓ S3 JSONL exports (365-day lock)                               │
│ ✓ API response signing (Ed25519)                                │
├─────────────────────────────────────────────────────────────────┤
│ DAY 3-4 (Mar 15-16) → Testing Framework                         │
│ ✓ Jest + Supertest setup                                        │
│ ✓ 80+ unit tests (credential resolver, audit, OIDC)            │
│ ✓ 15+ integration tests (API + fallback)                        │
│ ✓ 80%+ code coverage achieved                                   │
├─────────────────────────────────────────────────────────────────┤
│ DAY 5 (Mar 17)   → Hands-Off Automation [PARALLEL with Day 3-4]│
│ ✓ Proactive token rotation (30min before expiry)                │
│ ✓ Pod auto-remediation (< 2min MTTR)                            │
│ ✓ Distributed lock (prevent race conditions)                    │
├─────────────────────────────────────────────────────────────────┤
│ DAY 6 (Mar 18)   → Security Hardening                           │
│ ✓ Pre-commit hook (prevent secret commits)                      │
│ ✓ Cosign image signing + verification                           │
│ ✓ Trivy container scanning (block HIGH/CRITICAL)                │
│ ✓ Credential rotation enforcement (≤30 days)                    │
├─────────────────────────────────────────────────────────────────┤
│ DAY 8 (Mar 20)   → Load Testing                                 │
│ ✓ k6 load test: 1000 concurrent users                           │
│ ✓ P95 latency < 200ms verified                                  │
│ ✓ 5 chaos scenarios pass                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📊 DAILY STANDUP TEMPLATE (15 min)

**Yesterday:** [What did I complete?]
- ✓ Completed tasks (with PR links)
- ❌ Blockers (ask for help immediately)

**Today:** [What will I complete?]
- 1. [Specific task + file path]
- 2. [Specific task + file path]
- 3. [Specific task + file path]

**Risks:** [Anything slowing us down?]
- No blockers / Waiting for X / Need approval from Y

**Example:**
```
Yesterday:
+ Merged PR #2477: Unified API response schema (8 endpoints updated)
+ Created TypeScript SDK generation pipeline
- Blocked on: OpenAPI spec sync (in progress)

Today:
1. Generate Python/Go SDKs (Task 1.3)
2. Update error code mapping (Task 1.5)
3. Deploy to staging + test CLI (Task 1.4)

Risks: SDK generation may take longer if OpenAPI spec not finalized.
```

---

## 🚨 ESCALATION TRIGGERS

**Call War Room If:**
- ❌ 2+ critical tests failing (can't merge)
- ❌ Database migration fails (rollback required)
- ❌ Security scan finds 5+ vulns (blocks go-live)
- ❌ Load test fails (< 500 concurrent users)
- ❌ API response schema doesn't match spec

**Notify CTO If:**
- ⚠️ Behind schedule > 12 hours
- ⚠️ Need to drop P1 items
- ⚠️ Need to delay go-live

---

## 💾 COMMIT CHECKLIST (Before Pushing)

**Every commit must:**
- [ ] Pass `npm test` (all tests pass)
- [ ] Pass `npm run lint` (no formatting issues)
- [ ] Have JSDoc for new functions
- [ ] Update CHANGELOG.md
- [ ] Commit message format: `type: description` (e.g., `feat: unified API response`)

**Before merging to main:**
- [ ] Code review (1 approval)
- [ ] CI pipeline passes
- [ ] Load test still passes (regression check)
- [ ] Security scan passes (no new vulns)

---

## 📈 DAILY METRICS TO TRACK

| Metric | Day 1 | Day 2 | Day 3 | Day 4 | Day 5 | Target (Day 10) |
|--------|--------|--------|--------|--------|--------|-----------------|
| **Coverage** | 5% | 10% | 40% | 80% | 80% | 80%+ |
| **P0 Done** | 25% | 50% | 75% | 75% | 100% | 100% |
| **Load (vus)** | 0 | 0 | 100 | 500 | 1000 | 1000+ |
| **Incidents** | — | 0 | 0 | 0 | 0 | 0 |

---

## 🔧 Useful Commands (Copy-Paste)

```bash
# Test suite
npm test                           # Unit tests
npm run test:integration          # Integration tests
npm run test:coverage             # Coverage report

# Build & Deploy
docker build -t backend:latest .
docker push gcr.io/nexusshield-prod/backend:latest
terraform plan; terraform apply   # Verify changes

# Check status
kubectl get pods -A               # K8s pod status
gcloud sql instances list          # Cloud SQL status
gcloud secrets list --project=nexusshield-prod  # GCP secrets
aws secretsmanager list-secrets   # AWS secrets

# Logs
kubectl logs -f deployment/backend  # Pod logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50  # Cloud Run logs

# Load test
k6 run tests/load/performance.js --vus 1000 --duration 10m
```

---

## ⚡ EMERGENCY PROCEDURES

**If database goes down:**
1. Check replication status: `gcloud sql instances describe prod-db-primary`
2. Promote standby: `gcloud sql instances promote-replica prod-db-standby`
3. Update connection string in backend
4. Restart pods: `kubectl rollout restart deployment/backend`

**If certificate expires:**
1. Generate new cert: `certbot renew`
2. Update GCP Load Balancer
3. Restart Cloud Run: `gcloud run deploy backend --image=... --region=us-central1`

**If all pods evicted (node failure):**
1. Check node status: `kubectl get nodes`
2. Drain node: `kubectl drain <node-name> --ignore-daemonsets`
3. Delete node: `gcloud compute instances delete <node-name>`
4. GKE auto-scales new node automatically

**If under DDoS attack:**
1. Enable Cloud Armor rate-limiting: `gcloud compute security-policies update default --enable-layer7-ddos-defense`
2. Add WAF rules
3. Increase Cloud CDN TTL temporarily

---

## 📞 CONTACT INFO

| Role | Name | Phone | Slack | Availability |
|------|------|-------|-------|--------------|
| **CTO** | [Name] | [Ph] | @cto | On-call 24/7 |
| **Backend Lead** | [Name] | [Ph] | @lead | 9 AM - 6 PM UTC |
| **DevOps** | [Name] | [Ph] | @devops | 9 AM - 6 PM UTC |
| **QA** | [Name] | [Ph] | @qa | 9 AM - 6 PM UTC |

---

## ✅ PRE-GO-LIVE CHECKLIST (March 22, 9 AM)

**Infra Ready:**
- [ ] Database replica healthy (lag < 100ms)
- [ ] S3 bucket configured (COMPLIANCE lock, 3 days of exports)
- [ ] Cloud SQL backups confirmed (>5 backups exists)
- [ ] SSL certs valid (not expiring in <30 days)
- [ ] DNS records point to correct IPs

**Application Ready:**
- [ ] All tests pass (unit + integration + E2E)
- [ ] Load test passes (1000+ concurrent users)
- [ ] Zero HIGH/CRITICAL vulns (security scan)
- [ ] All API endpoints respond in < 200ms (p95)
- [ ] Credentials all rotated < 30 days ago

**Team Ready:**
- [ ] Runbook walkthrough complete
- [ ] On-call engineer trained
- [ ] Escalation contacts confirmed
- [ ] Monitoring dashboards created + tested
- [ ] Backup comms (phones, personal Slack)

---

**Print this card. Bring to standup every day. Update metrics during standup.**

