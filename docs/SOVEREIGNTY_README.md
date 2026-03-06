# Sovereignty README

Purpose: Define the repository and platform-level policy for being 100% sovereign and self-serving.

Principles:
- No external SaaS for core CI/CD, Git hosting, artifact registries, or secrets management without explicit approval.
- All production CI runs, artifact storage, and logs must be hosted in-house or in dedicated customer-controlled infrastructure.
- Only approved external networks allowed; egress whitelists must be defined per environment.
- Use audited, signed artifacts and provenance for release.

Quick checklist:
- Inventory completed.
- Private registries planned (MinIO/Nexus/Artifactory).
- Self-hosted runners via Terraform/packer (modules present).
- Deploy GitOps controllers in-house.

For decision records and exceptions, see the `issues/epics/` folder.