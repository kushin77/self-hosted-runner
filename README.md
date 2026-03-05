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


**Status:** ✅ Production Ready — Awaiting Ops Secrets | **Last Updated:** 2026-03-05

---

## Overview

This repository contains Terraform modules, deployment automation, monitoring, and CI/CD configuration to run and operate self-hosted GitHub Actions runners at scale. It is intended for SRE/Platform teams who will operate the runner fleet and integrate it into an enterprise deployment pipeline.

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

---

## License & Contact

This project is maintained by the platform team. For questions or operational help, open an issue or ping the `#platform` Slack channel.

---

<!-- EOF -->
