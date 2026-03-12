# NEXUSSHIELD PORTAL + NEXUS ENGINE — INTEGRATION ROADMAP
## How the MVP Portal Evolves into the Full Intelligence Platform

**Created:** March 12, 2026  
**Status:** Phase -1 Portal Complete | Phase 0-1 NEXUS Engine Spec Ready  

---

## 🔗 CONNECTION MAP

```
┌─ NEXUSSHIELD PORTAL (PHASE -1) ────────────────────────┐
│                                                          │
│ What we built: 45 files, React UI, Express API         │
│ Purpose: Beautiful, clean interface                     │
│ Status: MVP complete, type-safe, deployable            │
│                                                          │
│ Packages:                                              │
│  • @nexus/core (types, events, logging)                │
│  • @nexus/api (REST backend)                           │
│  • @nexus/frontend (React UI)                          │
│  • @nexus/products/ops (services)                      │
│  • @nexus/diagram-engine (foundation)                  │
│                                                          │
└────────────────────┬─────────────────────────────────┘
                     │ (evolves into)
                     ▼
┌─ NEXUS ENGINE (PHASES 0-4) ──────────────────────────┐
│                                                      │
│ What we're building: Actual intelligence layer      │
│ Purpose: Transform raw failure data into relief     │
│ Status: Architecture spec complete                  │
│                                                      │
│ Evolution:                                          │
│  Phase 0: Kafka + discovery + Slack skeleton        │
│  Phase 1: Perfect discovery + Studio dashboard      │
│  Phase 2: Slack Command Center + suggestions        │
│  Phase 3: Arsenal Fix + Optimizer + 4 engines       │
│  Phase 4: Sovereign product + multi-chat + draw.io  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## 📊 WHAT THE PORTAL UI BECOMES WITH NEXUS LOGIC

**Current Portal (MVP):**
- Dashboard with stats
- Deployments list
- Secrets manager
- Observability tab
- Empty diagram section
- Settings

**After Phase 1 (with NEXUS discovery):**
- **Dashboard** → "My Stuff" view (personalized to user) + Studio dashboard (ops view)
- **Deployments** → unified across GitHub, GitLab, Jenkins, Bitbucket, sovereign GitLab
- **Secrets** → integrated with Vault/GSM + drift detection
- **Observability** → real-time metrics per pipeline
- **Diagrams** → draw.io embedded (Phase 3-4)
- **AI Oracle** (new) → suggestions + fixes
- **Settings** → multi-tenant configuration

**After Phase 2 (with Slack):**
- Portal becomes secondary UI (Slack is primary for 80% of interactions)
- Slack commands trigger everything Portal can do
- Rich notifications from Slack back into Portal

**After Phase 3 (with Arsenal + Optimizer):**
- One-click fixes appear everywhere a failure is shown
- Hygiene meter on every repo
- Optimizer suggestions on every slow pipeline
- Draw.io IDE for visual editing

---

## 🏗️ INTEGRATION POINTS (How they wire together)

### 1. Core Types & Events System
**File:** `packages/core/src/types.ts` + `packages/core/src/events.ts`

**How it evolves:**
- Currently: Basic IDeployment, ISecret, IAlert types
- Phase 0: Add NexusDiscoveryEvent, environment tagging, cost tracking
- Phase 1: Add pipeline graph structures, failure classifications
- Phase 2: Add suggestion + confidence score types
- Phase 3: Add fix context, validation results

```typescript
// Currently
interface IDeployment {
  id: string;
  status: "success" | "failed" | "running";
  createdAt: Date;
}

// After Phase 0
interface NexusDiscoveryEvent {
  id: string;
  source: "github" | "gitlab" | "jenkins" | "bitbucket";
  tenant_id: string;
  run: IPipelineRun;
  environment: "dev" | "staging" | "prod" | "custom";
  cost?: { amount: number; currency: string };
  tags: Record<string, string>;
}

// After Phase 3
interface IAutoFixSuggestion {
  confidence: number; // 0-1
  patch: string;  // unified diff
  explanation: string;
  auto_merge_safe: boolean;
  rollback_available: boolean;
}
```

### 2. API Backend Evolution
**File:** `packages/api/src/app.ts`

**Current endpoints (Phase -1):**
```
GET  /health
GET  /api/v1/products
GET  /api/v1/ops/deployments
GET  /api/v1/ops/secrets
GET  /api/v1/ops/observability/status
```

**Phase 0 additions:**
```
POST /api/v1/ingestion/webhook/github      # ← Kafka sink
POST /api/v1/ingestion/webhook/gitlab      # ← Kafka sink
GET  /api/v1/discovery/runs                # ← unified query
GET  /api/v1/discovery/pipelines/{id}      # ← full context
```

**Phase 1 additions:**
```
GET  /api/v1/discovery/environments        # ← env-aware
GET  /api/v1/discovery/costs               # ← cost attribution
GET  /api/v1/studio/dashboard              # ← rich dashboard data
```

**Phase 2 additions:**
```
POST /api/v1/slack/events                  # ← Slack app integration
POST /api/v1/slack/interactions            # ← button/modal handling
GET  /api/v1/suggestions/{run_id}          # ← ML suggestions
```

**Phase 3 additions:**
```
POST /api/v1/fix/arsenal                   # ← multi-issue repairs
POST /api/v1/fix/optimizer                 # ← pipeline optimization
GET  /api/v1/hygiene/score                 # ← repo health
```

### 3. Storage Layer
**Currently:** In-memory mock data (Portal MVP)

**Phase 0 adds:**
```
PostgreSQL (Aurora or self-hosted)
├── tenants (tenant isolation)
├── runs (pipeline executions)
├── steps (job-level details)
├── costs (cost attribution)
├── failures (failure classification)
└── audit_log (tenant actions)

ClickHouse (analytics)
├── event_fact (immutable events)
├── metrics_daily (aggregations)
└── trace_logs (structured logs)

Redis Cluster
├── live_state (current run status)
├── suggestions_cache (ML results)
└── pub/sub (realtime)

S3
└── raw_logs/* (7-year immutable)
```

### 4. Frontend Integration
**File:** `packages/frontend/src/Portal.tsx`

**Current tabs (Phase -1):**
- Dashboard (stats + overview)
- Deployments (list with status)
- Pipelines (mock shows "Coming soon")
- Secrets (basic list)
- Observability (mock)
- Diagrams (empty)
- Infrastructure (mock)
- Settings

**Phase 1 updates:**
```tsx
// Tab switches to show real data from /api/v1/discovery/*
// "Deployments" becomes unified view across all sources
// "Pipelines" renders DAG from discovery data
// "My Stuff" tab added (personalized to current user)
// Studio view added (ops dashboard)
// Real-time WebSocket updates

const [activeTab, setActiveTab] = useState("my-stuff"); // default changes
const [discoveryData, setDiscoveryData] = useState(null);

useEffect(() => {
  // Subscribe to /api/v1/discovery updates via WebSocket
  const ws = new WebSocket("ws://localhost:5000/api/v1/discovery/stream");
  ws.onmessage = (ev) => setDiscoveryData(JSON.parse(ev.data));
}, []);
```

**Phase 2 updates:**
```tsx
// "AI Oracle" tab added (suggestions panel)
// Slack integration status shown
// "Slack Command Center" help panel

const [suggestions, setSuggestions] = useState([]);
const [slackConnected, setSlackConnected] = useState(false);
```

**Phase 3 updates:**
```tsx
// "Hygiene Meter" widget on every repo view
// "Optimize" button on pipelines
// "Fix with Nexus" button on failures
// Draw.io modal for visual editing

const [hygiene, setHygiene] = useState(null);
const [fixModal, setFixModal] = useState({open: false});
```

### 5. Database Schema Inheritance
**Phase -1 (current):** Mock in-memory

**Phase 0 migration:**
```sql
-- Create tenant isolation
CREATE TABLE tenants (
  id UUID PRIMARY KEY,
  name STRING,
  gitlab_url STRING,      -- for sovereign instances
  github_org STRING,       -- for cloud
  created_at TIMESTAMP
);

-- Core discovery tables
CREATE TABLE runs (
  id UUID PRIMARY KEY,
  tenant_id UUID FK,
  source ENUM ('github', 'gitlab', 'jenkins', 'bitbucket'),
  repo STRING,
  branch STRING,
  status ENUM ('success', 'failed', 'running'),
  duration_ms INT,
  cost DECIMAL,
  started_at TIMESTAMP,
  completed_at TIMESTAMP
);

CREATE TABLE steps (
  id UUID PRIMARY KEY,
  run_id UUID FK,
  name STRING,
  status ENUM ('success', 'failed', 'skipped'),
  duration_ms INT,
  runner_type STRING,       -- x86, arm64, gpu
  created_at TIMESTAMP
);

-- Add to existing IDeployment concept
CREATE TABLE failure_analysis (
  id UUID PRIMARY KEY,
  run_id UUID FK,
  root_cause STRING,
  suggested_fix STRING,
  confidence FLOAT,
  created_at TIMESTAMP
);
```

### 6. Event Bus Integration
**Currently:** Local EventBus in @nexus/core

**Phase 0 evolution:**
```typescript
// Current (local)
export class EventBus extends EventEmitter {
  emit(event: IEvent): boolean { ... }
}

// Phase 0 (Kafka-backed for multi-instance)
export class KafkaEventBus implements IEventBus {
  async emit(event: NexusEvent): Promise<void> {
    await this.kafka.send({
      topic: "nexus.pipeline.events",
      messages: [{ value: JSON.stringify(event) }]
    });
  }

  async subscribe(topic: string, handler: EventHandler): Promise<void> {
    const consumer = this.kafka.consumer({groupId: "nexus-core"});
    consumer.on(topic, (msg) => handler(JSON.parse(msg.value)));
  }
}
```

---

## 📈 RESOURCE ESTIMATION (to move from Portal to Full NEXUS)

| Component | Phase | Weeks | Engineers | Notes |
|-----------|-------|-------|-----------|-------|
| Kafka + Ingestion | 0 | 3 | 1 backend | Core plumbing |
| PostgreSQL + ClickHouse | 0 | 2 | 1 backend | Schema + RLS |
| Slack App + basic bot | 0 | 2 | 1 full-stack | /nexus status + webhook |
| Discovery normalizer | 0 | 3 | 1 backend | Idempotent schema |
| "My Stuff" dashboard | 1 | 2 | 1 frontend | Simple React view |
| Studio dashboard (pragmatic) | 1 | 4 | 1 frontend | No FlowCI yet |
| Slack Command Center | 2 | 3 | 1 full-stack | All commands |
| Arsenal Fix (narrow) | 3 | 4 | 1 backend + 1 ML | Env vars only |
| Repo Hygiene Meter | 3 | 3 | 1 backend | Aggregations |
| Pipeline Optimizer | 3 | 5 | 1 backend + 1 ML | Graph optimization |
| Draw.io integration | 4 | 4 | 1 full-stack | Embed + validator |
| **TOTAL to "magic" moment** | **3** | **~9 weeks / 2-3 engineers** | **Lean team** |

---

## 🚀 ACTUAL EXECUTION PLAN (Next 30 days)

**Week 1:**
- Set up Kafka locally + schema
- GitHub webhook ingestion (basic)
- PostgreSQL schema for runs/steps

**Week 2:**
- GitLab webhook ingestion
- Normalizer (handles GitHub/GitLab format differences)
- Basic test with real repo

**Week 3–4:**
- Update Portal API (`packages/api/src/app.ts`) to add:
  - POST /api/v1/ingestion/webhook/* endpoints
  - GET /api/v1/discovery/runs (query from PostgreSQL)
- Wire Portal frontend to real discovery data
- Create Slack App + /nexus status command (reads from discovery DB)

**Week 5+:**
- Based on what you learn about your own pipelines, pick Phase 1 (discovery-first) or jump straight to Slack Command Center
- Iterate on feedback

---

## ✅ FILES THAT CHANGE

**Existing files to update:**
- `packages/api/src/app.ts` → add webhook endpoints + discovery queries
- `packages/core/src/types.ts` → add NexusDiscoveryEvent + cost tracking
- `packages/frontend/src/Portal.tsx` → add "My Stuff" view + real data loading
- Docker / CI (no changes, still works)

**New files to create (Phase 0):**
- `internal/kafka/` (Go) → Kafka consumer/producer
- `internal/ingestion/` (Go) → GitHub/GitLab/Jenkins webhook handlers
- `internal/normalizer/` (Go) → schema v2.0 logic
- `database/migrations/` → PostgreSQL + ClickHouse
- `services/slack-bot/` (Go) → Slack app server

---

## 🎓 HOW TO DECIDE WHAT TO BUILD FIRST

**Option A: Discovery-first (Recommended)**
- Spend weeks 1–4 building perfect Kafka + discovery
- Portal shows real, unified pipeline data
- Slack bot sends meaningful notifications
- You learn your actual failure patterns
- Then decide on AI engines based on real data

**Option B: Slack Command Center first**
- Spend weeks 1–3 building Slack + GitLab trigger
- `/nexus deploy` and `/nexus retry` work
- Get immediate "thank God" from team
- Less polished discovery initially
- Good if you just want quick wins

**Option C: Draw.io visual IDE first**
- Spend weeks 1–3 embedding draw.io
- Engineers can visually edit + validate pipelines
- Different VoW but potentially powerful
- Harder to show ROI without discovery backend

**I recommend Option A** (discovery-first) because:
1. Everything else depends on good data
2. You learn what your actual pain points are
3. Later AI models will be better trained on real patterns
4. Non-ops people get immediate value (unified visibility)

---

## 🎬 FINAL CALL

**The Portal MVP you built is solid foundation.**

Now you're deciding: do you want to:
1. ✅ **Build the intelligence layer** (NEXUS Engine) that turns Portal into a real platform?
2. ✅ **Start with discovery** (boring but essential)?
3. ✅ **Or focus on one narrow win** (Slack Deploy command) first?

All three paths are valid. But the first path is the most defensible long-term and most likely to create the "thank God this exists" moment.

**What does your gut tell you the team needs most right now?**
- Unified visibility of all pipelines? → Discovery-first
- Quick deploy from Slack? → Command Center first
- Visual pipeline IDE? → Draw.io first

Pick one. I'll give you the code skeleton to start Week 1.

---

**Status: Portal MVP ✅ | NEXUS Engine specs ✅ | Ready to start Phase 0 🚀**
