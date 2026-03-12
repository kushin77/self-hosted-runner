Policy: GitHub Actions Disabled — Use Cloud Build for CI/CD

Overview
- GitHub Actions are DISALLOWED for this repository. All CI/CD, build, and deployment must run via Cloud Build or other approved CI (e.g., GitLab CI) under centralized ops control.
- Rationale: enforce centralized credential management (GSM/Vault/KMS), immutable audit trail, and standardized deployment pipelines.

Requirements
- Do not add or enable workflows under `.github/workflows/`.
- Use `cloudbuild.yaml` and `cloudbuild/*` templates for builds and deployments.
- Store secrets in Google Secret Manager, HashiCorp Vault, or KMS-backed secrets only.
- All deployments must be direct (no GitHub Releases or Actions-triggered releases).

Enforcement
- Any attempt to add a workflow will be reverted and archived.
- Maintain a single source of truth for CI: `cloudbuild/` and `scripts/ops/`.

Contact
- Ops owners: @kushin77, @BestGaaS220
