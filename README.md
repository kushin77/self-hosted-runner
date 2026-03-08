# self-hosted-runner

Production-grade infrastructure and automation for self-hosted GitHub Actions runners, including provisioning, observability, security, and lifecycle tooling.

> **WebSocket Security**: when running the provisioner metrics server with real-time updates, set `SOCKET_AUTH_TOKEN` in the environment. Clients must authenticate by supplying the same token in `socket.handshake.auth.token` or via an `Authorization: Bearer` header.
>
> For extra protection, run the socket service over TLS/WSS by setting `SOCKET_TLS=true` and providing certs via `SOCKET_CERT_PATH`/`SOCKET_KEY_PATH` or inline `SOCKET_CERT`/`SOCKET_KEY`. Secrets can also be stored in Vault and fetched at startup with `VAULT_ADDR`, `VAULT_TOKEN`, and paths `SOCKET_TOKEN_VAULT_PATH` and `SOCKET_CERT_VAULT_PATH`.
>
> **Monitoring**: the server now exports socket metrics at `/metrics` and `/metrics/summary`:
> `provisioner_socket_connections_total`, `provisioner_socket_disconnections_total`, `provisioner_socket_auth_failures_total`, `provisioner_socket_rate_limit_total`, and `provisioner_socket_tls_errors_total`. These counters are also included in the JSON summary under `socket`.
>
> **Load testing**: a simple load test script is available at `services/provisioner-worker/tests/socket_load_test.js` and can be run with `npm --prefix services/provisioner-worker run test:load -- <port> <clients>`.


**Status:** ✅ Production Ready — Using Self-Hosted Runner | **Last Updated:** 2026-03-05

## CI Status

[![Observability E2E](https://github.com/kushin77/self-hosted-runner/actions/workflows/observability-e2e.yml/badge.svg)](https://github.com/kushin77/self-hosted-runner/actions/workflows/observability-e2e.yml)


---

## Overview

This repository has been migrated to use a self-hosted runner infrastructure. All CI/CD workflows run locally on designated [self-hosted, linux] nodes for enhanced security and performance. See [docs/SELF_HOSTED_MIGRATION_SUMMARY_2026.md](docs/SELF_HOSTED_MIGRATION_SUMMARY_2026.md) for details.

---

## Quick Start (for Ops)

Prerequisites:
- Git, Terraform (1.5+), kubectl (if deploying to k8s), appropriate cloud CLI and credentials.

Steps:
1. Clone the repo:

   git clone https://github.com/kushin77/self-hosted-runner.git
   cd self-hosted-runner

2. Place required secrets (see `docs/PHASE_P2_OPS_QUICK_START.md`): `GOOGLE_CREDENTIALS`, `PROD_TFVARS`, `SLACK_WEBHOOK_URL`, `PAGERDUTY_SERVICE_KEY`.

3. Preview infrastructure changes:

   cd terraform/environments/production
   terraform init
   terraform plan -var-file=prod.tfvars

4. Apply after review:

   terraform apply -var-file=prod.tfvars

5. Run the E2E/observability checks (see `tests/` and `docs/PHASE_2_3_OPS_RUNBOOK.md`).

---

## Operational Handoff Resources

- Rollout checklist: [Issue #240](https://github.com/kushin77/self-hosted-runner/issues/240)
- Ops execution & secrets: [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241)
- Terraform apply runbook: [docs/PHASE_2_3_OPS_RUNBOOK.md](docs/PHASE_2_3_OPS_RUNBOOK.md)
- Final handoff summary: [docs/PHASE_P3_FINAL_HANDOFF.md](docs/PHASE_P3_FINAL_HANDOFF.md)

---

## Contributing

If you are contributing updates or fixes:
- Open a branch: `git checkout -b feat/your-change`
- Run linters and tests under `tests/`
- Create a PR and link relevant issues; include terraform plan output for infra changes.

## Feature Completion Dashboard

This repository tracks feature completion and readiness status in a concise dashboard for maintainers. The dashboard includes columns for design, implementation, tests, security review, and production readiness. See the project board or open issues for current status.

## Environment Variables

The following environment variables are commonly referenced by scripts and docs in this repo. They should be defined in CI or retrieved from Vault in production deployments:

- `GITHUB_OWNER` — GitHub organization or user owning the repo
- `GITHUB_TOKEN` — Token for automation (use GitHub Actions secrets; never commit tokens)
- `VAULT_ADDR` — HashiCorp Vault address (e.g., https://vault.example)
- `VAULT_ROLE_ID` / `VAULT_SECRET_ID` — AppRole credentials used by workflows
- `SOCKET_AUTH_TOKEN` — Auth token for provisioner socket (dev only)

References to secret names and vault paths are documented in `docs/` (see `docs/PHASE_P2_OPS_QUICK_START.md` and `docs/IMMUTABLE_EPHEMERAL_IDEMPOTENT.md`).

---

## Resources & Support

### Documentation
- 📖 **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** — Provider setup, OIDC, monitoring, troubleshooting
- 📋 **[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md)** — Architecture, modules, testing, phased rollout (5 phases)
- 📊 **[CI_CD_GOVERNANCE_GUIDE.md](CI_CD_GOVERNANCE_GUIDE.md)** — Git governance standards + 120+ rules

### GitHub Issues
- [#1912](https://github.com/kushin77/self-hosted-runner/pull/1912) — Orchestration framework
- [#1924](https://github.com/kushin77/self-hosted-runner/pull/1924) — Integration adapters
- [#1929](https://github.com/kushin77/self-hosted-runner/pull/1929) — Credential providers
- [#1928](https://github.com/kushin77/self-hosted-runner/pull/1928) — GitHub adapters
- [#1930](https://github.com/kushin77/self-hosted-runner/pull/1930) — CI/CD pipeline
- [#1938](https://github.com/kushin77/self-hosted-runner/pull/1938) — Observability

### Self-Hosted Runner (Ops)
- Rollout checklist: [Issue #240](https://github.com/kushin77/self-hosted-runner/issues/240)
- Ops execution & secrets: [Issue #241](https://github.com/kushin77/self-hosted-runner/issues/241)
- Terraform runbook: [docs/PHASE_2_3_OPS_RUNBOOK.md](docs/PHASE_2_3_OPS_RUNBOOK.md)
- Final handoff: [docs/PHASE_P3_FINAL_HANDOFF.md](docs/PHASE_P3_FINAL_HANDOFF.md)

### Getting Help
- 🐛 **Issues:** [GitHub Issues](https://github.com/kushin77/self-hosted-runner/issues)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/kushin77/self-hosted-runner/discussions)
- 🔒 **Security:** Report to security@example.com
- 💬 **Slack:** #platform channel

---

## License & Contact

This project is maintained by the platform team. For questions or operational help, open an issue or ping the `#platform` Slack channel.

---

<!-- EOF -->\n\n<- Duplicate state changes or workflow-refresh: 2026-03-07T15:49:53Z -->\n\n\n<- Duplicate state changes or workflow-refresh: 2026-03-07T15:50:12Z -->\n\n\n<- Duplicate state changes or workflow-refresh: 2026-03-07T15:50:35Z -->\n