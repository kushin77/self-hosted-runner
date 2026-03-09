# 📚 Documentation Hub

Welcome to the central documentation hub for the self-hosted-runner project.

## 🚀 Getting Started

- **New to this project?** Start with [runbooks/QUICKSTART.md](runbooks/QUICKSTART.md) (5-minute setup)
- **First time contributing?** See [../CONTRIBUTING.md](../ElevatedIQ-Mono-Repo/apps/portal/node_modules/recharts/CONTRIBUTING.md)
- **Need a quick reference?** Jump to [Quick Links](#quick-links) below

---

## 📖 Documentation by Purpose

### 🔧 Operational Runbooks
**For operators and maintainers — "How do I...?" guides**

| Runbook | Purpose |
|---------|---------|
| [runbooks/DEPLOYMENT_RUNBOOK.md](runbooks/DEPLOYMENT_RUNBOOK.md) | Deploy changes safely to production |
| [runbooks/SECRETS_ROTATION_POLICY.md](runbooks/SECRETS_ROTATION_POLICY.md) | Rotate/manage secrets (Vault, GSM, KMS) |
| [runbooks/OBSERVABILITY_E2E_PAGERDUTY_SETUP.md](runbooks/OBSERVABILITY_E2E_PAGERDUTY_SETUP.md) | Monitor health & set up alerts |
| [runbooks/DR_AUTOMATION_ORCHESTRATION.md](runbooks/DR_AUTOMATION_ORCHESTRATION.md) | Disaster recovery procedures |
| [runbooks/ERROR_CODES_GUIDE.md](runbooks/ERROR_CODES_GUIDE.md) | Common issues & solutions |

**Quick Links:**
- [runbooks/AUTOMATION_RUNBOOK.md](../scripts/automation/AUTOMATION_RUNBOOK.md)
- [runbooks/CONFIGURATION_GUIDE.md](runbooks/CONFIGURATION_GUIDE.md)
- [runbooks/CI_CD_GOVERNANCE_GUIDE.md](runbooks/CI_CD_GOVERNANCE_GUIDE.md)
- [runbooks/DEVELOPER_SECRETS_GUIDE.md](runbooks/DEVELOPER_SECRETS_GUIDE.md)

---

### 🏗️ Architecture & Design
**For engineers and architects — "Why are things built this way?" docs**

| Document | Focus |
|----------|-------|
| [architecture/GCP_GSM_ARCHITECTURE.md](architecture/GCP_GSM_ARCHITECTURE.md) | AWS, GCP, Azure, on-prem integration |
| [architecture/GSM_AWS_CREDENTIALS_ARCHITECTURE.md](architecture/GSM_AWS_CREDENTIALS_ARCHITECTURE.md) | Credentials management architecture |
| [architecture/SELF_HEALING_SYSTEM_100X.md](architecture/SELF_HEALING_SYSTEM_100X.md) | Security posture & self-healing |
| [architecture/EPHEMERAL_CREDENTIAL_SYSTEM_INFRA-2000.md](architecture/EPHEMERAL_CREDENTIAL_SYSTEM_INFRA-2000.md) | Immutable, self-destructing runner design |
| [architecture/PORTAL_DESIGN_REFERENCE.md](architecture/PORTAL_DESIGN_REFERENCE.md) | Portal and UI architecture |

---

### 🏛️ Architecture Decision Records (ADRs)
**Why we made specific technical choices**

*(ADRs are being populated in [decisions/](./decisions/))*

---

### 📦 Repository Root Links

- [../CONTRIBUTING.md](../ElevatedIQ-Mono-Repo/apps/portal/node_modules/recharts/CONTRIBUTING.md) — Contribution guidelines & standards
- [../CHANGELOG.md](../ElevatedIQ-Mono-Repo/apps/portal/node_modules/functions-have-names/CHANGELOG.md) — Version history & breaking changes
- [../README.md](../self_healing/README.md) — Project overview

---

## 📋 Quick Links

### For Developers
- [runbooks/QUICKSTART.md](runbooks/QUICKSTART.md) — Local development setup (5 min)
- [../CONTRIBUTING.md](../ElevatedIQ-Mono-Repo/apps/portal/node_modules/recharts/CONTRIBUTING.md) — Branch strategy, PR process
- [runbooks/CI_CD_GOVERNANCE_GUIDE.md](runbooks/CI_CD_GOVERNANCE_GUIDE.md) — Workflow standards

### For Operators
- [runbooks/AUTOMATION_RUNBOOK.md](../scripts/automation/AUTOMATION_RUNBOOK.md) — How to run automations
- [runbooks/DEPLOYMENT_READY.md](archive/DEPLOYMENT_READY.md) — Pre-deployment checklist
- [runbooks/CONFIGURATION_GUIDE.md](runbooks/CONFIGURATION_GUIDE.md) — Environment setup

### For Security
- [runbooks/DEVELOPER_SECRETS_GUIDE.md](runbooks/DEVELOPER_SECRETS_GUIDE.md) — Secret handling best practices
- [runbooks/GIT_GOVERNANCE_STANDARDS.md](runbooks/GIT_GOVERNANCE_STANDARDS.md) — Access controls & audit

### For Architecture & Design
- [architecture/PROJECT_OVERVIEW.md](architecture/PROJECT_OVERVIEW.md)
- [architecture/ROADMAP.md](../actions-runner/externals.2.332.0/node24/lib/node_modules/npm/node_modules/smart-buffer/docs/ROADMAP.md)
- [architecture/RUNNERCLOUD_VISION.md](architecture/RUNNERCLOUD_VISION.md)

---

## 📚 Historical Reference (Archive)

Looking for phase completion reports or historical status updates?
→ See [archive/](./archive/) directory

The archive is organized by phase and contains:
- [Archive Phases](./archive/phases/)
- [Completion Reports](./archive/completion-reports/)
