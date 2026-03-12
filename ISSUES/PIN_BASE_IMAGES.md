Title: Pin Base Images and Dependencies

Summary:
Pin Docker base images and critical dependency versions to improve reproducible builds and security scanning. Add automation to refresh pins and open PRs periodically.

Scope:
- Pin `node:20-alpine` to a digest or narrower tag in `backend/Dockerfile.prod` and any other Dockerfile.
- Pin frontend base image and toolchain images used in `cloudbuild.yaml` (e.g., `node:18-alpine`).
- Add dependency pinning and dependabot/renovate config for npm packages.

Suggested steps:
1. Record current digests for base images and update Dockerfiles to use digests or fixed minor versions.
2. Add an automated bot (Dependabot or Renovate) to manage dependency updates and pin PRs.
3. Add SBOM generation step to CI and run image scanning (Trivy/Container Analysis).

Assignee: infra/security
Labels: infra, security, maintenance
