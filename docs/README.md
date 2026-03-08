# 📚 Self-Hosted Runner Documentation Hub

**Welcome!** This is your central hub for all self-hosted runner documentation. Choose your path below:

---

## 🚀 Getting Started

- **New to this project?** Start with [QUICKSTART.md](../QUICKSTART.md) (5-minute setup)
- **First time contributing?** See [../CONTRIBUTING.md](../CONTRIBUTING.md)
- **Need a quick reference?** Jump to [Quick Links](#quick-links) below

---

## 📖 Documentation by Purpose

### 🔧 Operational Runbooks
**For operators and maintainers — "How do I...?" guides**

| Runbook | Purpose | Last Updated |
|---------|---------|--------------|
| [runbooks/deployment-runbook.md](runbooks/deployment-runbook.md) | Deploy changes safely to production | - |
| [runbooks/secrets-rotation.md](runbooks/secrets-rotation.md) | Rotate/manage secrets (Vault, GSM, KMS) | - |
| [runbooks/observability-monitoring.md](runbooks/observability-monitoring.md) | Monitor health & set up alerts | - |
| [runbooks/dr-recovery-runbook.md](runbooks/dr-recovery-runbook.md) | Disaster recovery procedures | - |
| [runbooks/troubleshooting.md](runbooks/troubleshooting.md) | Common issues & solutions | - |

**Quick Links from Root:**
- [AUTOMATION_RUNBOOK.md](../AUTOMATION_RUNBOOK.md)
- [CONFIGURATION_GUIDE.md](../CONFIGURATION_GUIDE.md)
- [CI_CD_GOVERNANCE_GUIDE.md](../CI_CD_GOVERNANCE_GUIDE.md)
- [DEVELOPER_SECRETS_GUIDE.md](../DEVELOPER_SECRETS_GUIDE.md)

---

### 🏗️ Architecture & Design
**For engineers and architects — "Why are things built this way?" docs**

| Document | Focus |
|----------|-------|
| [architecture/multi-cloud-design.md](architecture/multi-cloud-design.md) | AWS, GCP, Azure, on-prem integration |
| [architecture/services-overview.md](architecture/services-overview.md) | Microservices architecture (8 services) |
| [architecture/security-model.md](architecture/security-model.md) | Security posture: OIDC, workload ID, secrets management |
| [architecture/ephemeral-runners.md](architecture/ephemeral-runners.md) | Immutable, self-destructing runner design |
| [architecture/observability-stack.md](architecture/observability-stack.md) | Prometheus, Grafana, Datadog integration |

---

### 🏛️ Architecture Decision Records (ADRs)
**Why we made specific technical choices**

| ADR | Decision |
|-----|----------|
| [decisions/001-ephemeral-runners.md](decisions/001-ephemeral-runners.md) | Why use ephemeral, self-destructing runners instead of persistent? |
| [decisions/002-vault-over-gsm.md](decisions/002-vault-over-gsm.md) | Why Vault + GSM instead of direct cloud secret management? |
| [decisions/003-immutable-infrastructure.md](decisions/003-immutable-infrastructure.md) | Why immutable Dockerfile → no state drift |

---

### 📦 Related Guides (at repo root)

- [CONTRIBUTING.md](../CONTRIBUTING.md) — Contribution guidelines & standards
- [CHANGELOG.md](../CHANGELOG.md) — Version history & breaking changes
- [README.md](../README.md) — Project overview

---

## 📋 Quick Links

### For Developers
- [QUICKSTART.md](../QUICKSTART.md) — Local development setup (5 min)
- [CONTRIBUTING.md](../CONTRIBUTING.md) — Branch strategy, PR process
- [CI_CD_GOVERNANCE_GUIDE.md](../CI_CD_GOVERNANCE_GUIDE.md) — Workflow standards

### For Operators
- [AUTOMATION_RUNBOOK.md](../AUTOMATION_RUNBOOK.md) — How to run automations
- [DEPLOYMENT_READY.md](../DEPLOYMENT_READY.md) — Pre-deployment checklist
- [CONFIGURATION_GUIDE.md](../CONFIGURATION_GUIDE.md) — Environment setup

### For Security
- [DEVELOPER_SECRETS_GUIDE.md](../DEVELOPER_SECRETS_GUIDE.md) — Secret handling best practices
- [CI_CD_GOVERNANCE_GUIDE.md](../CI_CD_GOVERNANCE_GUIDE.md) — Access controls & audit
- [architecture/security-model.md](architecture/security-model.md) — Security design

### For Architecture & Design
- [architecture/multi-cloud-design.md](architecture/multi-cloud-design.md)
- [architecture/services-overview.md](architecture/services-overview.md)
- [architecture/ephemeral-runners.md](architecture/ephemeral-runners.md)

---

## 📚 Historical Reference (Archive)

Looking for phase completion reports or historical status updates?
→ See [archive/](archive/) directory

The archive is organized by phase and contains:
- Phase completion reports (Phases 1-8)
- Historical deployment status snapshots
- Handoff summaries
- Maintenance records

**Note:** Archive is *read-only* for historical reference. Active docs are in the directories above.

---

## 🔍 Finding What You Need

**Use this matrix to find docs fast:**

| I want to... | Go to... |
|-------------|----------|
| Get the system running locally | [QUICKSTART.md](../QUICKSTART.md) |
| Deploy to production | [runbooks/deployment-runbook.md](runbooks/deployment-runbook.md) |
| Rotate secrets/keys | [runbooks/secrets-rotation.md](runbooks/secrets-rotation.md) |
| Understand the architecture | [architecture/](architecture/) |
| Fix a broken deployment | [runbooks/troubleshooting.md](runbooks/troubleshooting.md) |
| Contribute code | [../CONTRIBUTING.md](../CONTRIBUTING.md) |
| Check status/history | [archive/](archive/) |

---

## 📝 Documentation Standards

**This repository follows these conventions:**

- ✅ **Living docs** (runbooks/) are kept up-to-date on every release
- ✅ **Architecture docs** explain *why* decisions were made
- ✅ **ADRs** record important technical decisions
- ✅ **Archive** is immutable — history is read-only
- ✅ All docs use **Markdown** with consistent formatting
- ✅ Internal links are **always relative** (for portability)
- ✅ Code examples are **copy-paste ready** and tested

---

## 🤝 Helping Improve Docs

Found an issue? Have a suggestion?

1. **Submit a PR** to fix typos or update content
2. **Open an issue** for documentation gaps
3. **Discuss in PRs** if you need clarification

Remember: **Good docs save lives** (and debug time). Help us keep them sharp! 🚀

---

## 📞 Support

- **Questions?** Check the [Quick Links](#quick-links) section
- **Bug found?** File an issue on GitHub
- **Feature request?** Open a discussion

---

*Last updated: 2026-03-08*  
*Documentation version: 1.0*  
*For the self-hosted runner project*
