# self-hosted-runner

Complete, production-grade infrastructure and automation tooling for self-hosted GitHub Actions runners with advanced monitoring, health management, and security controls.

**Status:** ✅ Production Ready — Awaiting Ops Secrets | **Last Updated:** 2026-03-05

---

## 🚀 Quick Access (Operational Handoff)

* **Rollout Master Checklist**: [Issue #240](https://github.com/kushin77/self-hosted-runner/issues/240)
* **Ops Execution Checklist (Secrets)**: [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241)
* **Final Handoff Summary**: [docs/PHASE_P3_FINAL_HANDOFF.md](docs/PHASE_P3_FINAL_HANDOFF.md)
* **Terraform Apply Guide**: [docs/PHASE_2_3_OPS_RUNBOOK.md](docs/PHASE_2_3_OPS_RUNBOOK.md)

---

## 📊 Feature Completion Dashboard

| Feature | Status | Completion | Notes |
|---------|--------|------------|-------|
| Multi-tier Runner Provisioning | ✅ | 100% | `ubuntu-latest` & `high-mem` — Terraform IaC complete |
| Terraform Infrastructure as Code | ✅ | 100% | Full IaC (AWS/GCP) with modules and production-ready defaults |
| Zero-Trust (GCP/Vault) | ✅ | 100% | KMS/GCS-backed Vault with auditable Service Account provisioning |
| Observability Stack (P3) | ✅ | 100% | Prometheus v2.45, Alertmanager, Grafana (dashboards automated) |
| Supply-Chain & SLSA | ✅ | 100% | SBOM (CycloneDX), SLSA Provenance, Gated Promotions |
| E2E Testing Framework | ✅ | 100% | Ephemeral Docker-based validation for all major flows |

---

## 🏗️ Getting Started (Operations)

### 1. Configure Repository Secrets
Follow [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241) to populate the following in GitHub Actions:
- `GOOGLE_CREDENTIALS`
- `PROD_TFVARS`
- `SLACK_WEBHOOK_URL`
- `PAGERDUTY_SERVICE_KEY`

### 2. Validation & Deployment
Run the following GitHub Actions workflows on `main`:
1. **Terraform Plan**: Review changes for sign-off (Issue #231)
2. **Observability E2E**: Verify alert routing to Slack/PagerDuty
3. **Terraform Apply**: Provision production infrastructure

---

## 🛠️ Project Structure

- `terraform/`: Root infrastructure for AWS Runners and GCP Vault backend
- `scripts/automation/pmo/prometheus/`: Modern monitoring & alerting stack
- `scripts/supplychain/`: SLSA/SBOM automation tools
- `docs/`: Comprehensive architectural and operational documentation

---

## 🤝 Contribution & Maintenance
This repository follows Phase-based engineering delivery.  
- **Current Phase**: Phase P3 (Complete)
- **Upcoming**: Phase P4 (Advanced Hardening & Multi-Tenancy)
