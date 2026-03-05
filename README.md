# self-hosted-runner

Complete, production-grade infrastructure and automation tooling for self-hosted GitHub Actions runners with advanced monitoring, health management, and security controls.

> **WebSocket Security**: when running the provisioner metrics server with real-time updates, set `SOCKET_AUTH_TOKEN` in the environment. Clients must authenticate by supplying the same token in `socket.handshake.auth.token` or via an `Authorization: Bearer` header.


**Status:** ✅ Production Ready — Awaiting Ops Secrets | **Last Updated:** 2026-03-05

---

## 🚀 Quick Access (Operational Handoff)

* **Rollout Master Checklist**: [Issue #240](https://github.com/kushin77/self-hosted-runner/issues/240)
* **Ops Execution Checklist (Secrets)**: [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241)
* **Final Handoff Summary**: [docs/PHASE_P3_FINAL_HANDOFF.md](docs/PHASE_P3_FINAL_HANDOFF.md)
* **Terraform Apply Guide**: [docs/PHASE_2_3_OPS_RUNBOOK.md](docs/PHASE_2_3_OPS_RUNBOOK.md)

---

## 📊 Feature Completion Dashboard

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-tier Runner Provisioning | ✅ | `ubuntu-latest` & `high-mem` pools wired via Terraform.
| Terraform Infrastructure as Code | ✅ | Fully modular AWS/GCP stacks with audited variables & outputs.
| Zero-Trust (GCP/Vault) | ✅ | KMS-/GCS-backed Vault with auditable service-account module.
| Observability Stack (P3) | ✅ | Prometheus v2.45 + Alertmanager + Grafana dashboards deployed.
| Supply-Chain & SLSA | ✅ | CycloneDX SBOMs, provenance verification, gated release workflows.
| E2E Testing Framework | ✅ | Ephemeral Docker tests exercising monitoring + alert routing.

---

## 🏗️ Getting Started (Operations)

1. **Configure Secrets** — Follow [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241) and add:
   - `GOOGLE_CREDENTIALS`
   - `PROD_TFVARS`
   - `SLACK_WEBHOOK_URL`
   - `PAGERDUTY_SERVICE_KEY`
2. **Validate** — Run GitHub Actions on `main`:
   1. Terraform Plan (review before apply; see [Issue #231](https://github.com/kushin77/self-hosted-runner/issues/231)).
   2. Observability E2E (real receiver validation).
   3. Terraform Apply (production rollout once plans are signed off).
3. **Post-Apply** — Confirm dashboards, targets, and alert receivers remain healthy via the E2E suite.

---

## 📚 Supporting References

* `docs/PHASE_P3_FINAL_HANDOFF.md` — Detailed architecture + handoff instructions.
* `docs/PHASE_2_3_OPS_RUNBOOK.md` — Step-by-step Terraform apply/runbook guidance.
* `docs/PHASE_P2_OPS_QUICK_START.md` — GCP Vault operational quick start.
* `docs/PROJECT_COMPLETION_SUMMARY.md` — Holistic delivery overview across phases.

---

## 🤝 Lifecycle Notes

* **Current Phase**: Phase P3 — Engineering delivery is locked and awaiting Ops execution.
* **Next Phase**: Phase P4 — Advanced hardening and multi-tenancy isolation (roadmap recorded in [Issue #243](https://github.com/kushin77/self-hosted-runner/issues/243)).
