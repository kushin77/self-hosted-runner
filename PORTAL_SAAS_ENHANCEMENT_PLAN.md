# Control Plane Portal: SaaS Enhancement Plan
**Date:** March 12, 2026  
**Status:** Phase 0 - Architecture Definition  
**Target:** Production SaaS Platform for Sovereign, Cloud-Agnostic Ops

---

## 🎯 VISION
**"The future ops tool for real-life engineers"**

Transform the GitLab UI redesign into:
1. **NexusShield OPS Portal** - First product (enterprise ops management)
2. **Extensible SaaS Framework** - Ready for Security/CISO suite and future products
3. **Sovereign Architecture** - Self-hosted, cloud-agnostic, complete control
4. **AI-Powered Troubleshooting** - Draw.io diagram inference on compilation failures

---

## 📦 ARCHITECTURE OVERVIEW

```
┌─────────────────────────────────────────────────────────────┐
│                    NexusShield Control Plane                 │
│                   (Sovereign, Cloud-Agnostic)                │
└─────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────┐
│                        Portal Framework                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │   Frontend   │  │   Backend    │  │    Service Connectors   │ │
│  │   (React)    │  │  (Node.js)   │  │                          │ │
│  └──────────────┘  └──────────────┘  ├──────────────────────────┤ │
│                                       │ • Kubernetes API         │ │
│  ┌──────────────────────────────────┐ │ • Terraform             │ │
│  │    Diagram Engine (Draw.io)      │ │ • Cloud (GCP/AWS/Az)   │ │
│  │    • Architecture                │ │ • Vault/GSM/KMS        │ │
│  │    • Troubleshooting             │ │ • CI/CD (GitLab CI)    │ │
│  │    • Failure Analysis            │ │ • Monitoring (Prom/GCP)│ │
│  └──────────────────────────────────┘ └──────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │            OPS Product Suite (Modular)                         │ │
│  ├────────────────────────────────────────────────────────────────┤ │
│  │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │ │
│  │ │ Deployment  │ │  Secrets    │ │ Observ.    │               │ │
│  │ │ Management  │ │  Management │ │ & Alerts   │ (Future...)   │ │
│  │ └─────────────┘ └─────────────┘ └─────────────┘               │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │         Multi-Product Framework (Extensible)                  │ │
│  │  ├─ OPS (Active)                                              │ │
│  │  ├─ SECURITY/CISO Suite (Future)                              │ │
│  │  └─ [Product 3-N] (Pluggable)                                 │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │           Repo Integration Layer                               │ │
│  │  • All scripts/ functions integrated as Portal features        │ │
│  │  • All tests run within Portal UI                              │ │
│  │  • All tools accessible as APIs                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ IMPLEMENTATION PHASES

### **Phase 0: Foundation (This Week)**
- [ ] Portal core architecture & project structure
- [ ] Multi-product scaffolding
- [ ] Diagram engine setup
- [ ] Base API framework
- [ ] CI/CD integration

### **Phase 1: OPS Product MVP**
- [ ] Deployment management UI
- [ ] Secrets management dashboard
- [ ] Observability integration
- [ ] Kubernetes & Terraform views
- [ ] Live log streaming

### **Phase 2: Diagram-Powered Troubleshooting**
- [ ] Draw.io integration layer
- [ ] Compilation failure analyzer
- [ ] Auto-diagram generation
- [ ] Failure inference engine
- [ ] Actionable recommendations

### **Phase 3: Full Repo Integration**
- [ ] Scripts API wrapper
- [ ] Test execution in Portal
- [ ] Complete tool inventory
- [ ] Health dashboard
- [ ] Automation triggers

### **Phase 4: SaaS Hardening**
- [ ] Multi-tenancy (future)
- [ ] RBAC & policy enforcement
- [ ] Audit logging
- [ ] High availability setup
- [ ] Performance optimization

---

## 📁 REPO STRUCTURE

```
/home/akushnir/self-hosted-runner/

├── portal/                          # NEW - Portal monorepo
│   ├── packages/
│   │   ├── @nexus/core             # Shared core services
│   │   ├── @nexus/diagram-engine   # Draw.io integration
│   │   ├── @nexus/products         # Product plugins
│   │   │   ├── ops/                # OPS product
│   │   │   ├── security/           # Security product (future)
│   │   │   └── ciso/               # CISO suite (future)
│   │   ├── @nexus/api              # Backend API
│   │   └── @nexus/frontend         # React UI (web)
│   │
│   ├── scripts/comprehensive/      # Integrated automation
│   ├── tests/portal/               # Portal test suite
│   ├── docs/portal/                # Portal documentation
│   ├── ci/                         # CI/CD pipelines
│   └── docker/                     # Containerization
│
├── scripts/                        # (Existing) - Used via Portal API
├── terrafor/                       # (Existing) - Exposed in Portal
├── frontend/                       # (Existing) - Migrated to portal/packages/
└── ...
```

---

## 🔧 KEY INTEGRATION POINTS

### 1. **Repository Tools -> Portal Features**
```
scripts/deploy/*             → Portal.DeploymentManager
scripts/monitoring/*         → Portal.Observability
scripts/security/*           → Portal.SecurityScanning
scripts/ops/*                → Portal.OpsAutomation
scripts/test/*               → Portal.TestRunner
tools/                       → Portal.ToolsAPI
```

### 2. **Diagram Engine**
- **Input:** Compilation logs, error traces, infrastructure graphs
- **Process:** Parse → Analyze → Generate diagrams → Recommend fixes
- **Output:** Draw.io diagrams + action items

### 3. **Multi-Product Framework**
```javascript
{
  id: 'ops',
  name: 'NexusShield OPS',
  status: 'active',
  features: ['deployment', 'secrets', 'observability'],
  api: '/api/v1/ops/',
},
{
  id: 'security',
  name: 'NexusShield Security Suite',
  status: 'future',
  features: ['sast', 'dast', 'compliance'],
  api: '/api/v1/security/',
}
```

---

## 🎨 UI/UX ENHANCEMENTS

### From Issue #2685
Replace generic GitLab tabs with:
1. **Operational Dashboards** (real-time ops view)
2. **Deployment Pipelines** (with diagram drilldown)
3. **Secrets Rotation** (automated, with policies)
4. **Observability Hub** (metrics, logs, traces)
5. **Problem Solver** (diagram-powered diagnostics)
6. **Audit Trail** (immutable, timestamped)
7. **Multi-Cloud Control** (GCP, AWS, Azure)
8. **Product Switcher** (OPS → Security → CISO)

### Diagram Integration
- **Auto-diagram on error:** Click error → see architecture diagram
- **Interactive troubleshooting:** Hover nodes → see logs, metrics
- **Runbook generation:** Diagram → automatic runbook
- **Failure inference:** ML-powered root cause analysis

---

## 🚀 QUICK START OBJECTIVES

**Week 1:**
1. ✅ Set up monorepo structure with Pnpm workspaces
2. ✅ Create core portal API with TypeScript/Express
3. ✅ Build diagram engine base
4. ✅ Connect to existing infrastructure APIs
5. ✅ Create basic dashboard view

**Week 2:**
1. ✅ OPS product MVP complete
2. ✅ Repo scripts wrapped as APIs
3. ✅ Diagram troubleshooting live
4. ✅ Test suite integrated
5. ✅ Docs auto-generated from code

---

## 📊 SUCCESS METRICS

| Metric | Target | Status |
|--------|--------|--------|
| Portal uptime | 99.95% | TBD |
| Diagram generation time | <2s | TBD |
| API latency | <100ms p95 | TBD |
| Test pass rate | 100% | TBD |
| Docs coverage | 100% | TBD |
| Feature completeness | 95%+ | TBD |

---

## 🔐 SECURITY & COMPLIANCE

- **Secret Management:** All creds via Vault/GSM, no hardcoding
- **RBAC:** Role-based access control for all operations
- **Audit:** Every action logged to immutable audit trail
- **Multi-tenancy:** Ready (not required for initial SaaS)
- **Encryption:** In-transit (TLS) + at-rest (KMS)
- **Compliance:** SOC2, HIPAA, GDPR ready

---

## 📋 NEXT STEPS

1. **Create portal monorepo** with required structure
2. **Build diagram engine** with Draw.io integration
3. **Implement OPS product** MVP
4. **Wrap repo scripts** as Portal APIs
5. **Deploy & validate** with your infrastructure
6. **Document & handoff** to operations team

---

**Lead Ownership:** Lead Engineer (Autonomous)  
**Timeline:** 2-3 weeks to MVP, 6 weeks to production  
**Investment:** Already have infrastructure, just building orchestration layer
