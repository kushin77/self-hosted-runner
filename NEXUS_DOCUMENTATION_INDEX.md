# NEXUS Platform — Master Documentation Index
## Complete Map | Portal MVP → Phase 0 Execution (March 12, 2026)

---

## 🎯 START HERE

**New to NEXUS?** Read these in order:

1. **[NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md)** (15 min read)
   - What just happened
   - What you now own (Portal MVP + Phase 0 codebase)
   - Immediate next steps (this week)
   - Honest assessment of what's real vs fantasy

2. **[NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md)** (30-45 min read)
   - Complete strategic vision
   - 10 AI engines explained
   - 4-phase implementation roadmap
   - Why this matters

3. **[NEXUS_PORTAL_INTEGRATION_ROADMAP.md](NEXUS_PORTAL_INTEGRATION_ROADMAP.md)** (20 min read)
   - How Portal MVP evolves into Platform
   - Architecture progression across phases
   - What gets built when

4. **[NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md)** (60+ min read for developers)
   - Day-by-day execution guide
   - Dependency mapping
   - Success criteria for each day
   - Testing strategy
   - Definition of done

---

## 📁 CODEBASE STRUCTURE

### Portal MVP (Complete) ✅
```
portal/
├── src/                    # React frontend + Express backend
├── docs/                   # Architecture, API, Getting Started
├── docker-compose.yml     # Local dev stack
├── package.json           # Dependencies
└── README.md             # Quick start
```

**Key Files:**
- [portal/README.md](portal/README.md) — How to run Portal locally
- [portal/docs/ARCHITECTURE.md](portal/docs/ARCHITECTURE.md) — System design
- [NEXUSSHIELD_PORTAL_COMPLETE_SUMMARY.md](NEXUSSHIELD_PORTAL_COMPLETE_SUMMARY.md) — Portal recap

### NEXUS Engine (Phase 0) 🚀
```
nexus-engine/
├── cmd/ingestion/         # Main webhook service (Go)
├── internal/
│   ├── kafka/             # Producer + Consumer
│   ├── normalizer/        # GitHub, GitLab, Jenkins converters
│   ├── db/                # PostgreSQL helpers
│   └── slack/             # Slack bot integration
├── proto/                 # Protocol Buffers (canonical schema)
├── database/migrations/   # PostgreSQL schema + RLS
├── test-fixtures/        # Example payloads
├── docker-compose.yml     # Full local stack
├── go.mod + go.sum       # Dependencies
├── Makefile              # Build targets
└── README.md             # Developer guide
```

**Key Files:**
- [nexus-engine/README.md](nexus-engine/README.md) — Getting started
- [nexus-engine/proto/discovery.proto](nexus-engine/proto/discovery.proto) — Data schema
- [nexus-engine/cmd/ingestion/main.go](nexus-engine/cmd/ingestion/main.go) — Main entry point
- [nexus-engine/Makefile](nexus-engine/Makefile) — Development commands

---

## 🎯 GITHUB ISSUES (Phase 0 Work Tracking)

| Issue | Title | Assigned To | Status |
|-------|-------|-------------|--------|
| [#2687](https://github.com/kushin77/self-hosted-runner/issues/2687) | Kafka Ingestion Pipeline | Backend Engineer | In Progress |
| [#2688](https://github.com/kushin77/self-hosted-runner/issues/2688) | PostgreSQL + ClickHouse Schema | DB Engineer | In Progress |
| [#2689](https://github.com/kushin77/self-hosted-runner/issues/2689) | Basic Slack Bot (/nexus command) | Full-Stack Engineer | Ready |
| [#2690](https://github.com/kushin77/self-hosted-runner/issues/2690) | Portal API Integration (discovery endpoints) | Backend Engineer | Ready |
| [#2691](https://github.com/kushin77/self-hosted-runner/issues/2691) | Discovery Normalizer (idempotent schema) | Backend Engineer | In Progress |
| [#2692](https://github.com/kushin77/self-hosted-runner/issues/2692) | Phase 0 Epic (umbrella tracking) | Project Manager | In Progress |

---

## 📚 STRATEGIC DOCUMENTATION

### Vision & Roadmap
- **[NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md)** 
  - Complete vision (10 AI engines, 4 phases, sovereign strategy)
  - What's real vs fantasy (honest assessment)
  - Why internal-first (dogfooding, trust-building)

### Integration & Evolution
- **[NEXUS_PORTAL_INTEGRATION_ROADMAP.md](NEXUS_PORTAL_INTEGRATION_ROADMAP.md)**
  - How Portal MVP becomes Platform
  - Phase 0 → Phase 4 architecture progression
  - When each component gets built

### Handoff & Launch
- **[NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md)**
  - Status summary
  - What you own (Portal + Phase 0)
  - Immediate next steps (this week)
  - Resource estimates

### Execution & Testing
- **[NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md)**
  - Day-by-day breakdown (3 weeks)
  - Dependencies & sequencing
  - Success criteria for each day
  - Testing strategy

---

## 🚀 GETTING STARTED (For Developers)

### Quick Start (15 minutes)
```bash
# 1. Clone the repo (you're already here)
cd self-hosted-runner

# 2. Read the overview
cat NEXUS_COMPLETE_HANDOFF.md | head -50

# 3. Go to Phase 0 codebase
cd nexus-engine

# 4. Read the developer guide
cat README.md

# 5. Start the local stack
make up            # Kafka + PostgreSQL + ClickHouse running
make db-migrate    # Create schema
make build         # Compile ingestion service
make run           # Listen on :8080
```

### Full Setup (30 minutes)
Follow [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) → Day 1 section

### Understanding the Architecture (60 minutes)
1. Read [NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md)
2. Read [nexus-engine/README.md](nexus-engine/README.md) architecture section
3. Review [nexus-engine/proto/discovery.proto](nexus-engine/proto/discovery.proto)
4. Skim [nexus-engine/internal/normalizer/github.go](nexus-engine/internal/normalizer/github.go)

---

## 📊 PROJECT STATUS

### Portal MVP (Complete) ✅
- **Status:** Production-ready
- **Files:** 45 across 6 packages
- **Lines:** ~10,000
- **Deployable:** Yes, immediately
- **Users:** Self-hosted team

### NEXUS Phase 0 (In Progress) 🚀
- **Status:** Scaffolding complete, development started
- **Files:** 11 core files created
- **Lines:** ~2,000
- **Timeline:** 3 weeks (March 12-April 2)
- **Success:** Real webhooks flowing → Portal → Slack

### Full Platform (Planned) 📋
- **Phase 1 (Discovery Dashboard):** April 2-16
- **Phase 2 (Command Center):** April 16-May 7
- **Phase 3 (Arsenal + Engines):** May 7-June 4
- **Phase 4 (Sovereign + Polish):** June 4+

---

## 🎯 WHO SHOULD READ WHAT

### Product Manager / Project Lead
1. [NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md) — Status + timeline
2. [NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md) — Full roadmap
3. [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) — Day-by-day plan

### Backend Engineer (Go)
1. [NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md) → "Next 72 hours"
2. [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) → Your assigned day
3. [nexus-engine/README.md](nexus-engine/README.md) → Full guide
4. [nexus-engine/proto/discovery.proto](nexus-engine/proto/discovery.proto) → Schema

### Database Engineer
1. [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) → Day 1 checklist
2. [nexus-engine/database/migrations/001_init_schema.sql](nexus-engine/database/migrations/001_init_schema.sql) → Schema
3. Review RLS policies

### Frontend Engineer (React/TypeScript)
1. [NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md) → Context
2. [portal/README.md](portal/README.md) → Portal getting started
3. [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) → Day 7 checklist (Portal API integration)

### DevOps / Infrastructure
1. [nexus-engine/docker-compose.yml](nexus-engine/docker-compose.yml) → Local dev
2. [nexus-engine/Makefile](nexus-engine/Makefile) → Commands
3. [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) → Deployment section (TBD Phase 1)

### Executive / Stakeholder
1. [NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md) — 5 min read
2. [NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md) → Vision sections only
3. [NEXUS_PORTAL_INTEGRATION_ROADMAP.md](NEXUS_PORTAL_INTEGRATION_ROADMAP.md) → Timeline + phases

---

## 🔗 CROSS-REFERENCES

### Strategic Issues
- GitHub Issue #2686 (original brainstorm with 8 expert comments) — [read online](https://github.com/kushin77/self-hosted-runner/issues/2686)

### Portal MVP Documentation
- [NEXUSSHIELD_PORTAL_COMPLETE_SUMMARY.md](NEXUSSHIELD_PORTAL_COMPLETE_SUMMARY.md) — Portal recap
- [portal/docs/ARCHITECTURE.md](portal/docs/ARCHITECTURE.md) — Portal system design
- [portal/README.md](portal/README.md) — Portal quick start

### NEXUS Phase 0 Documentation
- [nexus-engine/README.md](nexus-engine/README.md) — Complete developer guide
- [nexus-engine/proto/discovery.proto](nexus-engine/proto/discovery.proto) — Event schema
- [nexus-engine/Makefile](nexus-engine/Makefile) — All commands

---

## ⚡ QUICK COMMANDS

### Portal (MVP)
```bash
cd portal
npm install
make dev              # Start development server
make build            # Build for production
make test             # Run tests
```

### NEXUS Engine (Phase 0)
```bash
cd nexus-engine
make up               # Start all services (Kafka, PostgreSQL, ClickHouse)
make build            # Compile Go binary
make test             # Run unit tests
make test-integration # Run integration tests
make test-e2e         # Run end-to-end tests
make clean            # Stop services + cleanup
```

---

## 📈 SUCCESS METRICS

### Phase 0 (March 12-April 2)
- ✅ Real webhooks flowing end-to-end
- ✅ >85% unit test coverage
- ✅ Zero data leaks (RLS enforced)
- ✅ <1s latency (webhook → database)
- ✅ Deduplication proved (100% accuracy)
- ✅ All 6 GitHub issues closed
- ✅ Team trained + ready for Phase 1

### Phase 1+ (April 2 onwards)
- ✅ >50% of engineers use discovery dashboard daily
- ✅ Slack integration widely used for status checks
- ✅ Zero production incidents caused by CI/CD visibility gap

---

## 🆘 TROUBLESHOOTING

### Docker Container Issues
```bash
make clean            # Stop all containers
make up               # Fresh start
docker logs nexus-kafka
docker logs nexus-postgres
```

### Database Connection Issues
```bash
# Test connection
psql -h localhost -U postgres -d nexus -c "SELECT 1;"

# Check schema
psql -h localhost -U postgres -d nexus -c "\d"
```

### Kafka Issues
```bash
# List topics
docker exec nexus-kafka kafka-topics --list --bootstrap-server localhost:9092

# Check consumer lag
docker exec nexus-kafka kafka-consumer-groups --describe --group nexus-app --bootstrap-server localhost:9092
```

### Webhook Not Received
```bash
# Check ingestion service logs
docker logs nexus-ingestion

# Test endpoint manually
curl -X GET http://localhost:8080/health

# Check if signature verification is failing
# Look for "signature verification failed" in logs
```

---

## 📞 CONTACT & ESCALATIONS

**Phase 0 Lead:** [Assign]  
**Portal MVP Owner:** [Assign]  
**Architecture Lead:** [Assign]  
**Database Lead:** [Assign]  

---

## 📅 TIMELINE AT A GLANCE

| Phase | Dates | What Ships | Key Metric |
|-------|-------|-----------|-----------|
| **Phase 0** | Mar 12-Apr 2 | Discovery pipeline (Kafka, PostgreSQL, normalizer) | Real events flowing end-to-end |
| **Phase 1** | Apr 2-16 | Dashboard (multi-source, filters, real-time) | >50% daily active users |
| **Phase 2** | Apr 16-May 7 | Slack Command Center | Auto-remediation suggestions in Slack |
| **Phase 3** | May 7-Jun 4 | Arsenal + 2-3 engines | >10 auto-fixes per day |
| **Phase 4** | Jun 4+ | Sovereign product + polish | Enterprise-ready SaaS |

---

## ✅ VERIFICATION CHECKLIST

Before moving to Phase 1:

- [ ] All Phase 0 GitHub issues closed
- [ ] Real webhook → Portal flow verified
- [ ] Slack bot responding to live events
- [ ] >85% unit test coverage
- [ ] RLS tested + verified (no data leaks)
- [ ] Idempotency proven (3x same event = 1 DB row)
- [ ] <1s latency webhook → database
- [ ] Team trained on Phase 0 codebase
- [ ] Documentation complete + reviewed
- [ ] Staging environment mirrors production setup

---

## 🎬 LAST WORD

You now have everything to build Phase 0:
- ✅ Complete strategic vision ([NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md](NEXUS_ENGINE_COMPLETE_BRAINSTORM_CONSOLIDATION.md))
- ✅ Day-by-day execution guide ([NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md))
- ✅ Working codebase ([nexus-engine/](nexus-engine/))
- ✅ Honest assessment (no vaporware)
- ✅ GitHub issues tracking ([#2687-2692](https://github.com/kushin77/self-hosted-runner/issues/2687))

**Start with [NEXUS_COMPLETE_HANDOFF.md](NEXUS_COMPLETE_HANDOFF.md) or [NEXUS_PHASE0_RUNBOOK.md](NEXUS_PHASE0_RUNBOOK.md) depending on your role.**

---

**Status:** 🟢 READY TO EXECUTE  
**Next Milestone:** Phase 0 Complete (April 2, 2026)  
**Success Criteria:** "Real events, visible in Portal, within 1 second"

