# NexusShield - Enterprise Zero-Trust Orchestration Platform

**Complete control plane for multi-cloud credential management, CI/CD automation, and observability**

---

## 📋 Overview

NexusShield unifies credential management, CI/CD automation, and observability across AWS, GCP, and Azure with **zero-trust architecture** and **immutable audit trails**.

### Core Principles

- ✅ **Immutable**: All operations recorded in append-only JSONL audit trails (WORM storage)
- ✅ **Ephemeral**: All credentials expire in <60 seconds (no long-lived secrets)
- ✅ **Idempotent**: All operations safe to re-run without side effects
- ✅ **No-Ops**: Fully autonomous automation (zero manual intervention required)
- ✅ **Hands-Off**: Scheduled credential rotation, monitoring, compliance checks
- ✅ **Multi-Layer Credentials**: GSM → Vault → AWS KMS for defense-in-depth

---

## 🏗️ Project Structure

```
nexusshield/
├── portal/                          # NexusShield Unified Control Plane
│   ├── frontend/                    # React 18 UI (6 modules)
│   │   ├── src/
│   │   │   ├── components/          # 50+ component library
│   │   │   ├── pages/               # Dashboard, Vault, Orchestration, etc.
│   │   │   └── hooks/               # Data fetching + state management
│   │   └── package.json
│   │
│   └── backend/                     # Node.js/Express API
│       ├── src/
│       │   ├── routes/              # REST + GraphQL endpoints
│       │   ├── services/            # Business logic
│       │   ├── models/              # Database schemas
│       │   └── middleware/          # Authentication, logging, validation
│       └── package.json
│
├── infrastructure/                  # Deployment Automation
│   ├── credentials/                 # Multi-layer credential management
│   │   ├── gcp-secret-manager/      # Ephemeral token storage
│   │   ├── vault-integration/       # Dynamic secrets
│   │   └── aws-kms/                 # Encryption keys
│   │
│   ├── terraform/                   # Infrastructure as Code
│   │   ├── modules/                 # Reusable Terraform modules
│   │   │   ├── gcp-cloud-run/       # Portal backend deployment
│   │   │   ├── gcp-cloud-sql/       # PostgreSQL database
│   │   │   ├── gcp-cloud-armor/     # DDoS protection
│   │   │   └── monitoring/          # Prometheus + Grafana
│   │   │
│   │   ├── production/              # Production Terraform configs
│   │   │   └── main.tf              # Primary deployment
│   │   │
│   │   └── staging/                 # Staging Terraform configs
│   │       └── main.tf              # Pre-production testing
│   │
│   └── kubernetes/                  # K8s manifests (optional)
│
├── gtm/                             # Go-To-Market Infrastructure
│   ├── landing-page/                # Vercel/Netlify landing page
│   │   ├── src/
│   │   └── package.json
│   │
│   └── automation/                  # CRM + email automation
│       ├── hubspot-config/          # HubSpot setup
│       ├── workflows/               # Outreach sequences
│       └── dashboards/              # Sales metrics
│
├── scripts/                         # Automation Scripts
│   ├── credential-rotation.sh       # GSM/Vault/KMS rotation (runs every 60s)
│   ├── deploy.sh                    # Automated deployment
│   ├── validate.sh                  # Health checks
│   └── audit-trail.sh               # Audit log verification
│
├── logs/                            # Immutable Audit Trails
│   ├── credential-rotation-audit.jsonl    # Ephemeral token operations
│   ├── deployment-audit.jsonl             # Infrastructure changes
│   ├── compliance-audit.jsonl             # Compliance operations
│   └── access-audit.jsonl                 # User access log
│
├── docs/                            # Documentation
│   ├── NEXUSSHIELD_MASTER_PRODUCT_STRATEGY.md     # Full strategy
│   ├── NEXUSSHIELD_PORTAL_UI_ARCHITECTURE.md      # Design system
│   ├── NEXUSSHIELD_GTM_STRATEGY.md                # Sales playbook
│   └── ARCHITECTURE.md                            # Technical design
│
└── README.md                        # This file
```

---

## 🚀 Quick Start

### Phase 1: Portal MVP (Week 1-4)

**Deliverables:**
1. React 18 frontend with design system
2. Node.js/Express backend with GraphQL API
3. PostgreSQL database with immutable audit tables
4. OAuth2 + JWT authentication

**Prerequisites:**
- Node.js 18+
- GCP Project (Cloud Run, Cloud SQL, Secret Manager)
- Docker (for containerization)
- Terraform (for IaC)

**Deploy:**
```bash
# 1. Clone repository
git clone https://github.com/kushin77/self-hosted-runner.git
cd nexusshield

# 2. Frontend setup
cd portal/frontend
npm install
npm run dev              # Local development

# 3. Backend setup
cd ../backend
npm install
npm run migrate          # Database schema
npm run seed            # Sample data
npm run dev             # Local API (http://localhost:3000)

# 4. Deploy to GCP
cd ../../infrastructure/terraform/production
terraform plan
terraform apply

# 5. Verify deployment
curl https://nexusshield-portal-backend-prod.run.app/health
```

### Phase 2: GTM Infrastructure (Week 1-3)

**Deliverables:**
1. Landing page (Vercel/Netlify)
2. HubSpot CRM integration
3. Email outreach sequences
4. Customer discovery dashboard

**Deploy:**
```bash
cd nexusshield/gtm/landing-page
npm install
vercel deploy           # Deploy landing page

cd ../automation
# HubSpot setup (manual via UI)
# Email sequences configured in HubSpot
# Webhook integration for form submissions
```

### Phase 3: Credential Management (Week 1-2)

**Deliverables:**
1. Google Secret Manager integration
2. Vault dynamic secrets setup
3. AWS KMS encryption
4. Automated credential rotation (every 60s)

**Deploy:**
```bash
cd nexusshield/scripts

# Set up credential rotation
chmod +x credential-rotation.sh

# Run rotation manually (for testing)
./credential-rotation.sh

# Schedule with cron (every minute)
echo "*/1 * * * * /home/akushnir/self-hosted-runner/nexusshield/scripts/credential-rotation.sh" | crontab -

# Verify audit trail
tail -f logs/credential-rotation-audit.jsonl
```

---

## 🔒 Security & Compliance

### Credential Lifecycle

```
GSM (Ephemeral Token, <60s)
    ↓
Vault (Dynamic Secret, <60s)
    ↓
AWS KMS (Encryption, <60s)
    ↓
Destroy (Memory cleared, credentials invalidated)
    ↓
Audit Trail (Immutable JSONL record)
```

### Immutable Audit Trail (WORM)

All operations logged immutably in PostgreSQL (no deletes, no updates):

```json
{
  "timestamp": "2026-03-09T23:45:12.123Z",
  "operation": "credential-rotation",
  "status": "success",
  "user": "automation-system",
  "resource": "nexusshield-prod-db-password",
  "cloud_provider": "gcp",
  "details": {
    "credential_manager": "gsm",
    "ttl_seconds": 60,
    "rotation_id": "rot_20260309_234512",
    "next_rotation": "2026-03-09T23:46:12Z"
  }
}
```

### Compliance Ready

- ✅ **SOC 2 Type II**: Immutable audit trails, encrypted storage, access controls
- ✅ **HIPAA**: BAA available, PHI data protection, encryption in transit/at rest
- ✅ **PCI-DSS**: Credential management, audit logging, multi-factor authentication
- ✅ **ISO 27001**: Information security controls, incident response

---

## 📊 GitHub Issues & Progress Tracking

### Active Tracking Issues

- **#2177**: 🚀 NexusShield Portal MVP - Phase 1 Frontend & Backend
- **#2178**: 📊 NexusShield GTM Infrastructure - Phase 1 (CRM, Landing, Campaigns)
- **#2179**: ⚙️ NexusShield Infrastructure - Credentials & Automation (Phase 1)

**Update status:** Use `gh issue view #2177` to check progress

---

## 💰 Pricing & Revenue Model

| Tier | Price | Runners | Features |
|------|-------|---------|----------|
| **Free** | $0 | 3 | Read-only Vault |
| **Starter** | $499/mo | 10 | Full Vault + rotation |
| **Professional** | $1,999/mo | 50 | All + observability |
| **Enterprise** | Custom | 500+ | All + custom + SLA |

## 📈 5-Year Financial Projections

- **Year 1**: $480k ARR (25 customers, beta)
- **Year 2**: $1.44M ARR (60 customers)
- **Year 3**: $3.6M ARR (120 customers)
- **Year 4**: $6.4M ARR (200 customers)
- **Year 5**: $10.8M+ ARR (300+ customers)

---

## 🛠️ Development Roadmap

### Phase 1: MVP (April-May 2026)

- [ ] Week 1: React setup + design system
- [ ] Week 2: Dashboard + components
- [ ] Week 3: Vault UI + orchestration
- [ ] Week 4: Polish + deployment pipeline

### Phase 2: Growth (June-July 2026)

- [ ] Observability dashboard (Prometheus embed)
- [ ] Advanced RBAC (custom roles)
- [ ] Policy editor (branch rules, merge strategies)
- [ ] Scheduled automation

### Phase 3: Scale (August-Sep 2026)

- [ ] Multi-region failover
- [ ] Custom connector SDK
- [ ] White-label portal
- [ ] Marketplace

---

## 📖 Documentation

- [Master Product Strategy](./docs/NEXUSSHIELD_MASTER_PRODUCT_STRATEGY.md) - Full business + technical strategy
- [Portal UI Architecture](./docs/NEXUSSHIELD_PORTAL_UI_ARCHITECTURE.md) - Design system + components
- [GTM Strategy](./docs/NEXUSSHIELD_GTM_STRATEGY.md) - Sales playbook + customer discovery
- [Architecture](./docs/ARCHITECTURE.md) - Technical design details

---

## 🤝 Contributing

This is a private project. For access requests, contact the NexusShield team.

**Development Guidelines:**
- All changes must include immutable audit trail entries
- No long-lived credentials (max TTL: 60 seconds)
- All infrastructure deployed via Terraform (no manual changes)
- All operations logged immutably (append-only JSONL)

---

## 📞 Support & Questions

- **Slack**: #nexusshield (internal)
- **GitHub Issues**: Feature requests + bug reports
- **Email**: team@nexusshield.io

---

## 📝 License

Proprietary - NexusShield, 2026

---

**Last Updated:** 2026-03-09 | **Status:** Phase 1 Active Development
