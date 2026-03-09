# NexusShield Portal - UI/UX Architecture & Component Library

**Portal MVP Design System** | **Target Launch**: Q2 2026 | **Status**: DESIGN PHASE

---

## 1. DESIGN SYSTEM FOUNDATION

### 1.1 Visual Language

**Color Palette:**
```
PRIMARY (Security Blue):
├─ Primary: #0057B8 (Trust, authority)
├─ Light: #E3F2FD
├─ Dark: #003399
└─ Usage: CTAs, active states, primary UI

ACCENT (Success Green):
├─ Accent: #2E8C57 (Secure, compliant)
├─ Light: #E8F5E9
├─ Dark: #1B5E20
└─ Usage: Status indicators, checkmarks

WARNING (Alert Orange):
├─ Warning: #FF9800
├─ Light: #FFF3E0
├─ Dark: #E65100
└─ Usage: Alerts, action required, blockers

ERROR (Alert Red):
├─ Error: #D32F2F
├─ Light: #FFEBEE
├─ Dark: #B71C1C
└─ Usage: Failed operations, critical issues

NEUTRAL (Grayscale):
├─ Text Primary: #212121
├─ Text Secondary: #757575
├─ Bg Primary: #FFFFFF
├─ Bg Secondary: #F5F5F5
├─ Border: #E0E0E0
└─ Usage: Core content, typography, spacing
```

**Typography:**
```
Heading 1 (H1):  Roboto Bold 32px  (Page titles)
Heading 2 (H2):  Roboto Bold 24px  (Section titles)
Heading 3 (H3):  Roboto SemiBold 18px (Subsections)
Body Large:      Roboto Regular 16px  (Main content)
Body:            Roboto Regular 14px  (UI text)
Caption:         Roboto Regular 12px  (Metadata, timestamps)
Code/Mono:       JetBrains Mono 12px  (Logs, JSON, code)
```

**Spacing Scale (8px base):**
```
xs:  4px  (minimal padding)
sm:  8px  (compact spacing)
md:  16px (default spacing)
lg:  24px (loose spacing)
xl:  32px (section spacing)
2xl: 48px (major layout spacing)
```

**Shadows & Elevation:**
```
Elevation 1: 0 2px 4px rgba(0,0,0,0.1)
Elevation 2: 0 4px 8px rgba(0,0,0,0.12)
Elevation 3: 0 8px 16px rgba(0,0,0,0.15)
– Used for cards, modals, popovers
```

### 1.2 Component Library (React)

**Core Components (Built from Scratch or Shadcn/ui):**

```
✅ Layout Components
├─ AppShell (header + sidebar + main content)
├─ Header (top nav, user menu, search)
├─ Sidebar (navigation, collapsible on mobile)
├─ Container (grid layout, max-width)
└─ Grid/Flex (responsive layouts)

✅ Navigation
├─ Navbar (top navigation)
├─ Tabs (horizontal, vertical)
├─ BreadCrumbs (page hierarchy)
├─ SideNav (persistent navigation)
└─ Drawer (collapsible sidebar)

✅ Cards & Containers
├─ Card (default container)
├─ CardHeader (title + actions)
├─ CardBody (content area)
├─ CardFooter (action buttons)
└─ Panel (complex layout card)

✅ Data Display
├─ Table (sortable, filterable, paginated)
├─ List (simple, with icons)
├─ Timeline (vertical event list)
├─ Badge (labels, status)
├─ Chips (removable tags)
└─ Avatar (user profiles)

✅ Inputs & Forms
├─ TextInput (single line)
├─ TextArea (multi-line)
├─ Select (dropdown)
├─ Checkbox (multi-select)
├─ Radio (single-select)
├─ Toggle (on/off state)
├─ DatePicker (date selection)
├─ CodeEditor (inline code)
└─ SearchBox (filter/search)

✅ Buttons & Actions
├─ Button (primary, secondary, danger)
├─ ButtonGroup (icon buttons)
├─ IconButton (small, round)
├─ SplitButton (action + dropdown)
├─ LinkButton (text link style)
└─ FAB (floating action button)

✅ Feedback
├─ Alert (dismissible notification)
├─ Toast (temporary notification)
├─ Snackbar (bottom notification)
├─ Banner (page-level alert)
├─ Spinner (loading indicator)
├─ Progress (progress bar)
├─ Skeleton (content placeholder)
└─ Empty State (no data placeholder)

✅ Modals & Overlays
├─ Modal (dialog box)
├─ Drawer (side panel)
├─ Popover (floating tooltip)
├─ Tooltip (hover text)
├─ ContextMenu (right-click menu)
└─ Dropdown (menu list)

✅ Charts & Metrics
├─ LineChart (Recharts)
├─ BarChart (Recharts)
├─ PieChart (Recharts)
├─ MetricCard (KPI display)
├─ SparkLine (mini chart)
└─ Gauge (circular progress)

✅ Specialized
├─ Diff Viewer (code comparison)
├─ JSONViewer (collapsible JSON)
├─ TreeView (hierarchical list)
├─ Timeline (event sequence)
├─ Map (world map for multi-region)
└─ Org Chart (team hierarchy)
```

---

## 2. KEY SCREENS & FLOWS

### 2.1 Dashboard (Main Entry Point)

```
DASHBOARD LAYOUT:
┌─────────────────────────────────────────────────────────┐
│ 🏠 Dashboard  |  Vault  |  Orchestration  |  Observ.    │ (TopNav)
├────────┬──────────────────────────────────────────────────┤
│        │                                                  │
│ ☰ Nav  │  Welcome back, [User] | Filter: All Clouds 🔽  │ (Header)
│        │                                                  │
│   🏠   │┌──────────────────────────────────────────────┐  │
│   Dashboard│ ⚡ QUICK STATUS                             │  │
│        │├──────────────────────────────────────────────┤  │
│   🔐   ││ AWS       GCP         Azure      Vault       │  │
│   Vault│ │ ✅ ONLINE ✅ ONLINE  ⚠️  CONFIG   ✅ ONLINE   │  │
│        │ └──────────────────────────────────────────────┘  │
│   ⚙️   │┌──────────────────────────────────────────────┐  │
│   Orch.│ 📊 METRICS (Last 24h)                          │  │
│        │├──────────────────────────────────────────────┤  │
│   📊   ││ Deployments: 3 running  │ Runners: 28/50    │  │
│  Obs.  │ │ Secrets rotated: 12    │ CI/CD jobs: 184   │  │
│        │ │ Failures: 0             │ Uptime: 99.97%   │  │
│   🔓   │ └──────────────────────────────────────────────┘  │
│  Audit │┌──────────────────────────────────────────────┐  │
│        │ 🚨 ACTIVE ALERTS (5)                           │  │
│        │├──────────────────────────────────────────────┤  │
│   👥  │ │ ⚠️  Phase 3B: GCP quota warning (12 vCPU/100) │  │
│  Admin │ │ 🔴 Runner k8s-prod-01: Offline for 15m      │  │
│        │ │ 🟡 Vault: Token expiry in 2h                │  │
│        │ │ ℹ️  Prometheus: Metrics healthy              │  │
│        │ └──────────────────────────────────────────────┘  │
│        │┌──────────────────────────────────────────────┐  │
│        │ 📈 DEPLOYMENT TIMELINE (Recent)               │  │
│        │├──────────────────────────────────────────────┤  │
│        │ │ ✅ Phase 6 (Observability)  - 2h ago        │  │
│        │ │ ✅ Phase 3B (GCP Deploy)    - 5h ago        │  │
│        │ │ ✅ Phase 2 (Creds)          - 8h ago        │  │
│        │ └──────────────────────────────────────────────┘  │
│        │                                                  │
│        │ [View All] [Trigger Deployment]  [Settings]     │
│        │                                                  │
└────────┴──────────────────────────────────────────────────┘

Key Metrics Displayed:
├─ Top right: User menu + notifications + theme toggle
├─ Main grid: 6 cards (status, metrics, alerts, timeline, actions)
├─ Each card: Rich info density without overwhelming
└─ Footer: Quick links to all modules
```

**React Component Structure:**
```typescript
<Dashboard>
  <DashboardHeader user={user} filters={filters} />
  <StatusGrid clouds={['aws', 'gcp', 'azure', 'vault']} />
  <MetricsOverview period="24h" />
  <ActiveAlerts limit={5} onDismiss={} />
  <DeploymentTimeline recent={10} />
  <QuickActions />
</Dashboard>
```

### 2.2 Vault Secrets Management

```
VAULT HUB LAYOUT:
┌──────────────────────────────────────────────────────┐
│ 🔐 Vault  |  All Secrets (342)                       │
├──────────────────────────────────────────────────────┤
│ Filter: All Managers ▼  Search: aws_  [🔍]           │
│ Manager: ☑️ GSM ☑️ Vault ☑️ KMS  Status: ☑️ Active   │
├──────────────────────────────────────────────────────┤
│                                                      │
│ SECRET DIRECTORY                                    │
├──────────────────────────────────────────────────────┤
│ 📁 Production                                        │
│    📁 AWS                                            │
│       • prod-aws-access-key         (Vault)          │
│       • prod-aws-secret-key         (KMS - encrypted)│
│       └─ 🔄 Rotated: 2h ago ✅                       │
│    📁 GCP                                            │
│       • prod-gcp-sa-key             (GSM)            │
│       └─ ⚠️ Expires in 1h 45m                        │
│ 📁 Development                                       │
│    📁 Vault-Transit                                  │
│       • transit-key-v12             (Vault)          │
│       └─ 🔄 Rotated: 24h ago ✅                      │
│                                                      │
├────────────────────────────────────────────────────┤
│ SELECTED SECRET: prod-gcp-sa-key                    │
│                                                     │
│  Manager: Google Secret Manager     Env: Production │
│  Type: Service Account Key          Status: Active  │
│  Created: 2026-02-15 14:22:11 UTC                   │
│  Last Rotated: 2026-03-09 08:15:33 UTC              │
│  Next Rotation: 2026-03-16 08:15:33 UTC ⏱️ 6.5d    │
│  Rotation Policy: Every 7 days +    [Edit]          │
│  Access Count (30d): 1,247                          │
│  Last Accessed: 2 minutes ago (runner-prod-01)      │
│                                                     │
│  AUDIT LOG:                                         │
│  └─ Mar 09 08:15:33 Rotated by: automation-system   │
│     Status: Success (new key generated, old revoked)│
│  └─ Mar 08 08:15:11 Accessed by: prod-runner-01    │
│  └─ Mar 07 14:22:00 Updated policy: rotation every 7d
│                                                     │
│  [Show Value]  [Rotate Now]  [Revoke]  [Audit Trail]│
└──────────────────────────────────────────────────────┘
```

**Features:**
- Real-time search + filter
- Hierarchical folder tree
- Quick rotation trigger
- Full audit trail per secret
- Visual expiration warnings
- Copy-to-clipboard with masking
- Batch operations (rotate multiple)

### 2.3 Orchestration Control Center

```
ORCHESTRATION CONTROL:
┌──────────────────────────────────────────────────────┐
│ ⚙️  Orchestration  |  Phases  |  Executions           │
├──────────────────────────────────────────────────────┤
│ AVAILABLE PHASES:                                   │
├──────────────────────────────────────────────────────┤
│                                                      │
│ Phase 1: OIDC Migration (GCP WIF)                   │
│ Status: ⏳ In Progress  |  Est. Complete: 12h       │
│ ├─ Prerequisites:                                   │
│ │  └─ ✅ GCP IAM configured                          │
│ │  └─ ✅ GitHub OIDC provider registered            │
│ │  └─ ⏳ Waiting: Org admin approval (issue #2158)   │
│ ├─ Action: [View Details] [View Log]                │
│ └─ Estimated cost: $200/month                       │
│                                                      │
│ Phase 2: Credential Hardening (AppRole/JWT) 🔄     │
│ Status: 🟡 Blocked  |  Est. if triggered: 8h        │
│ ├─ Prerequisites:                                   │
│ │  └─ ⚠️  Phase 1 must complete first               │
│ │  └─ ✅ Vault AppRole roles defined                │
│ │  └─ ✅ JWT policy templates ready                 │
│ ├─ Risks:                                           │
│ │  └─ Will revoke all long-lived VAULT_TOKENs      │
│ │  └─ All services must re-auth (plan: 30m)        │
│ ├─ Action: [Simulate] [Schedule] [Execute Now]      │
│ └─ Estimated cost: $0 (no infra)                    │
│                                                      │
│ Phase 3B: GCP Infrastructure Deployment 🚀          │
│ Status: ✅ Complete  |  Last run: 6h ago             │
│ ├─ Resources:                                       │
│ │  └─ 8 GCP resources created (8/8 ✅)             │
│ │  └─ Terraform state: Managed + locked             │
│ │  └─ Monthly cost: $850/month                      │
│ ├─ Instances:                                       │
│ │  └─ runner-prod-01: us-central1-a (online ✅)     │
│ │  └─ runner-prod-02: us-central1-b (online ✅)     │
│ │  └─ runner-prod-03: us-central1-c (online ✅)     │
│ ├─ Action: [Scale Up] [Rollback] [Logs]             │
│ └─ Total provisioned: $850/month                    │
│                                                      │
│ Phase 6: Observability Stack Deployment 📊          │
│ Status: ✅ Complete  |  Last run: 2h ago             │
│ ├─ Infrastructure:                                  │
│ │  └─ ✅ Prometheus (scraping 28 targets)          │
│ │  └─ ✅ Grafana (15 dashboards, 3 users)          │
│ │  └─ ✅ ELK Stack (indices: 120, retention: 30d)  │
│ │  └─ ✅ PagerDuty (86 incidents managed)          │
│ ├─ Metrics:                                         │
│ │  └─ Ingestion: 45K metrics/min (healthy)         │
│ │  └─ Storage: 450GB (with 30-day retention)       │
│ │  └─ Query latency: p99 <500ms                    │
│ ├─ Action: [Add Data Source] [Scale] [Logs]         │
│ └─ Total cost: $2,100/month                         │
│                                                      │
│ [+ New Custom Phase] [View All]                     │
└──────────────────────────────────────────────────────┘

EXECUTION LOG:
Phase run #47 (2026-03-09 08:15:11 UTC)
├─ Phase 3B (GCP Deploy) — 1h 23m ✅
│  ├─ GCP quota check ...................... 2m ✅
│  ├─ Apply terraform (8 resources) ........ 45m ✅
│  ├─ Bootstrap runner automation ......... 12m ✅
│  ├─ Health check (3/3 passing) .......... 5m ✅
│  └─ Audit trail recorded (15 entries) ... <1m ✅
│
├─ Phase 6 (Observability) — 28m ✅
│  ├─ Prometheus validation ............... 3m ✅
│  ├─ Grafana dashboard sync ............. 5m ✅
│  ├─ ELK index template update ........... 7m ✅
│  ├─ PagerDuty integration check ......... 2m ✅
│  └─ Alert rules validation ............. 11m ✅
│
└─ Total Deployment Time: 1h 51m (within SLA ✅)
```

### 2.4 Audit Explorer

```
AUDIT EXPLORER:
┌──────────────────────────────────────────────────────┐
│ 🔓 Audit Logs  | 247 Entries | Export: PDF CSV JSON  │
├──────────────────────────────────────────────────────┤
│ Filters:                                            │
│ Cloud Provider: All ▼   Status: All ▼  Time Range ▼ │
│ Operation: All ▼         User: All ▼     [Clear All]│
│                                                      │
│ [Search: vault auth | 🔍]                           │
├──────────────────────────────────────────────────────┤
│ Showing 15 of 247 entries  [< 1 2 3 4 5 ... 17 >]   │
│                                                      │
│ Entry #247 (LATEST)                                 │
│ ┌────────────────────────────────────────────────┐ │
│ │ Timestamp: 2026-03-09 23:10:00 UTC             │ │
│ │ Operation: production-deployment-completion    │ │
│ │ Status: ✅ SUCCESS                             │ │
│ │ User: automation-system                        │ │
│ │ Cloud: gcp                                     │ │
│ │ Resource: phase-6-observability                │ │
│ │                                                │ │
│ │ Details:                                       │ │
│ │ {                                              │ │
│ │   "phase": "6",                                │ │
│ │   "components": [                              │ │
│ │     {"type": "prometheus", "status": "ok"},    │ │
│ │     {"type": "grafana", "status": "ok"},       │ │
│ │     {"type": "elk", "status": "ok"}            │ │
│ │   ],                                           │ │
│ │   "deployment_id": "phase-6-2026-03-09-23:10" │ │
│ │ }                                              │ │
│ │ [Expand Details] [View in Context] [Notify]    │ │
│ └────────────────────────────────────────────────┘ │
│                                                      │
│ Entry #246                                          │
│ ┌────────────────────────────────────────────────┐ │
│ │ Timestamp: 2026-03-09 22:50:00 UTC             │ │
│ │ Operation: phase-3b-admin-deployment           │ │
│ │ Status: ✅ SUCCESS                             │ │
│ │ User: automation-system                        │ │
│ │ Cloud: gcp                                     │ │
│ │ Resource: gcp-sa-prod-automation               │ │
│ │                                                │ │
│ │ Details | [Entry Log] | [Compliance Check ✅] │ │
│ │ [Expand] [Share] [Flag Issue]                 │ │
│ └────────────────────────────────────────────────┘ │
│                                                      │
│ [Load Previous Entries]                            │
└──────────────────────────────────────────────────────┘

COMPLIANCE MAPPING (Sidebar):
✅ Entry #247
   └─ SOC2: B.2.1 (Monitoring)
   └─ HIPAA: Audit log requirement
   └─ PCI-DSS: 10.1 (System activity)

Compliance Coverage: 97% (240/247 entries mapped)
```

---

## 3. TECHNICAL IMPLEMENTATION

### 3.1 Tech Stack

**Frontend:**
```
Framework:        React 18 + TypeScript
State Mgmt:       TanStack Query + Zustand
UI Library:       shadcn/ui + Tailwind CSS
Charts:           Recharts + D3.js
Code Editor:      Monaco Editor
Real-time:        Socket.io (WebSockets)
Build:            Vite
Testing:          Vitest + Testing Library
```

**Backend (Node.js/Express + TypeScript):**
```
Server:           Express.js + TypeScript
API:              REST + GraphQL (Apollo)
Database:         PostgreSQL + Redis (cache)
Auth:             Passport.js (OAuth2, JWT)
Logging:          Winston + Pino
Monitoring:       Datadog / New Relic
```

**Deployment:**
```
Containerization: Docker
Orchestration:    Kubernetes (optional)
CDN:              Cloudflare
Hosting:          AWS ECS / GCP Cloud Run
Database:         AWS RDS / GCP Cloud SQL
```

### 3.2 File Structure

```
nexusshield-portal/
├─ frontend/
│  ├─ src/
│  │  ├─ components/
│  │  │  ├─ Layout/
│  │  │  │  ├─ AppShell.tsx
│  │  │  │  ├─ Header.tsx
│  │  │  │  └─ Sidebar.tsx
│  │  │  ├─ Dashboard/
│  │  │  │  ├─ Dashboard.tsx
│  │  │  │  ├─ StatusGrid.tsx
│  │  │  │  ├─ MetricsOverview.tsx
│  │  │  │  ├─ AlertsPanel.tsx
│  │  │  │  └─ DeploymentTimeline.tsx
│  │  │  ├─ Vault/
│  │  │  │  ├─ VaultHub.tsx
│  │  │  │  ├─ SecretDirectory.tsx
│  │  │  │  ├─ SecretDetail.tsx
│  │  │  │  └─ RotationScheduler.tsx
│  │  │  ├─ Orchestration/
│  │  │  │  ├─ ControlCenter.tsx
│  │  │  │  ├─ PhasePanel.tsx
│  │  │  │  ├─ ExecutionLog.tsx
│  │  │  │  └─ TriggerModal.tsx
│  │  │  ├─ Audit/
│  │  │  │  ├─ AuditExplorer.tsx
│  │  │  │  ├─ AuditTable.tsx
│  │  │  │  ├─ AuditDetail.tsx
│  │  │  │  └─ ComplianceMapper.tsx
│  │  │  ├─ Common/
│  │  │  │  ├─ Button.tsx
│  │  │  │  ├─ Card.tsx
│  │  │  │  ├─ Table.tsx
│  │  │  │  ├─ Modal.tsx
│  │  │  │  └─ ... (50+ more)
│  │  ├─ pages/
│  │  │  ├─ DashboardPage.tsx
│  │  │  ├─ VaultPage.tsx
│  │  │  ├─ OrchestrationPage.tsx
│  │  │  ├─ AuditPage.tsx
│  │  │  ├─ ObservabilityPage.tsx
│  │  │  ├─ PoliciesPage.tsx
│  │  │  └─ SettingsPage.tsx
│  │  ├─ hooks/
│  │  │  ├─ useDeployments.ts
│  │  │  ├─ useSecrets.ts
│  │  │  ├─ useAuditLogs.ts
│  │  │  ├─ useMetrics.ts
│  │  │  └─ ... (20+ more)
│  │  ├─ services/
│  │  │  ├─ api.ts (REST client)
│  │  │  ├─ graphql.ts (GQL client)
│  │  │  ├─ websocket.ts
│  │  │  └─ auth.ts
│  │  ├─ types/
│  │  │  ├─ deployment.ts
│  │  │  ├─ audit.ts
│  │  │  ├─ credential.ts
│  │  │  └─ ... (10+ more)
│  │  ├─ store/
│  │  │  ├─ authStore.ts
│  │  │  ├─ uiStore.ts
│  │  │  ├─ deploymentStore.ts
│  │  │  └─ ... (5+ more)
│  │  ├─ styles/
│  │  │  ├─ globals.css
│  │  │  ├─ theme.ts
│  │  │  └─ ... (design tokens)
│  │  ├─ App.tsx
│  │  └─ main.tsx
│  ├─ public/
│  └─ package.json
│
├─ backend/
│  ├─ src/
│  │  ├─ routes/
│  │  │  ├─ deployments.ts
│  │  │  ├─ secrets.ts
│  │  │  ├─ audit.ts
│  │  │  ├─ metrics.ts
│  │  │  └─ auth.ts
│  │  ├─ controllers/
│  │  │  ├─ DeploymentController.ts
│  │  │  ├─ SecretController.ts
│  │  │  ├─ AuditController.ts
│  │  │  └─ MetricsController.ts
│  │  ├─ services/
│  │  │  ├─ DeploymentService.ts
│  │  │  ├─ VaultService.ts
│  │  │  ├─ GCPService.ts
│  │  │  ├─ AWSService.ts
│  │  │  ├─ AuditService.ts
│  │  │  └─ MetricsService.ts
│  │  ├─ models/
│  │  │  ├─ Deployment.ts
│  │  │  ├─ Secret.ts
│  │  │  ├─ AuditLog.ts
│  │  │  └─ ... (5+ more)
│  │  ├─ middleware/
│  │  │  ├─ auth.ts
│  │  │  ├─ errorHandler.ts
│  │  │  ├─ logging.ts
│  │  │  └─ validation.ts
│  │  ├─ graphql/
│  │  │  ├─ schema.graphql
│  │  │  ├─ resolvers/
│  │  │  └─ directives/
│  │  ├─ db/
│  │  │  ├─ connection.ts
│  │  │  ├─ migrations/
│  │  │  └─ seeds/
│  │  ├─ utils/
│  │  │  ├─ logger.ts
│  │  │  ├─ error.ts
│  │  │  ├─ validators.ts
│  │  │  └─ crypto.ts
│  │  ├─ app.ts
│  │  └─ server.ts
│  ├─ tests/
│  └─ package.json
│
└─ docker-compose.yml
```

### 3.3 Key API Endpoints

**GraphQL Queries:**
```
query GetDashboard($period: DateRange!) {
  dashboard {
    cloudStatus {
      aws { status, lastChecked }
      gcp { status, lastChecked }
      azure { status, lastChecked }
    }
    metrics(period: $period) {
      deploymentCount
      runnerCount
      secretRotationCount
    }
    activeAlerts { count, items }
    recentDeployments(limit: 10) { id, phase, status }
  }
}

query GetSecret($id: ID!) {
  secret(id: $id) {
    id, name, manager, status
    rotation { interval, lastRotated, nextRotation }
    auditLog { ... }
    usage { accessCount, lastAccessed }
  }
}

query ListAuditLogs($filter: AuditFilter!) {
  auditLogs(filter: $filter) {
    edges { node { id, timestamp, operation } }
    pageInfo { hasNextPage, endCursor }
  }
}
```

**REST Endpoints:**
```
GET  /api/v1/deployments          (list deployments)
POST /api/v1/deployments/trigger  (trigger phase)
GET  /api/v1/deployments/:id      (get deployment details)
GET  /api/v1/deployments/:id/logs (streaming logs)

GET  /api/v1/secrets              (list secrets)
POST /api/v1/secrets/:id/rotate   (rotate secret)
GET  /api/v1/secrets/:id/audit    (secret audit trail)

GET  /api/v1/audit                (list audit entries)
GET  /api/v1/audit/:id            (audit entry detail)
POST /api/v1/audit/export         (bulk export)

GET  /api/v1/metrics              (time-series metrics)
GET  /api/v1/compliance/report    (compliance status)
```

---

## 4. DEVELOPMENT ROADMAP

### Phase 1: MVP (4 weeks)
- Week 1: Design system setup + component library
- Week 2: Core layout (AppShell, nav, header) + auth
- Week 3: Dashboard + basic Vault viewer
- Week 4: GraphQL API + simple deployment triggers

### Phase 2: Core Features (6 weeks)
- Week 5-6: Full Vault management (secrets browser, rotation UI)
- Week 7-8: Orchestration control center (trigger phases, logs)
- Week 9-10: Audit explorer + compliance mapping

### Phase 3: Polish (3 weeks)
- Week 11: Real-time updates (WebSocket), notifications
- Week 12: Charts/metrics integration, performance optimization
- Week 13: Testing + documentation

---

## 5. ACCESSIBILITY & MOBILE

**WCAG 2.1 AA Compliance:**
- ✅ Color contrast (4.5:1 text)
- ✅ Keyboard navigation (Tab, Enter, Escape)
- ✅ Screen reader support (ARIA labels)
- ✅ Responsive design (mobile-first)

**Mobile Experience:**
- Responsive grid (1 column on mobile)
- Bottom nav (instead of sidebar)
- Touch-friendly buttons (56px minimum)
- Simplified charts (limited animations)

---

**Status**: Ready for designer review | **Figma Board**: [link upon creation]
