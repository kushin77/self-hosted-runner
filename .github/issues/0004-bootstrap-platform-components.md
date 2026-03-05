Title: Bootstrap platform components in GitOps skeleton

Description:
- Populate deploy/gitops-skeleton/ with production-grade manifests (ArgoCD operator, Tekton operator, Prometheus stack, OPA constraints library).
- Provide scripts and docs to bootstrap platform clusters and connect to central management.

Acceptance Criteria:
- Manifests and operator installs added under `deploy/gitops-skeleton/platform/`.
- `deploy/gitops-skeleton/platform/bootstrap.sh` provides operator steps and caveats.

## Status

Completed: 2026-03-05

Resolution: Platform manifests for ArgoCD, Tekton, OPA/Gatekeeper, and Prometheus were added under `deploy/gitops-skeleton/platform/`. Components validated in documentation and deployment guides.

Assignees: devops-platform
Labels: task, platform
