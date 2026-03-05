Kubernetes Reference Architecture for Autonomous CI/CD

Principles

- Multi-cluster, multi-tenant design using namespaces, network policies, and RBAC.
- GitOps-driven desired-state for apps and platform components.
- Declarative, CRD-first extensibility (Tekton, Argo Rollouts, OPA, Service Mesh).

Platform Components

- Git Repositories
  - `infrastructure/*` — cluster-level manifests
  - `apps/*` — application manifests with overlays for envs
  - `catalog/*` — developer templates

- Cluster Services
  - GitOps Operator: ArgoCD or Flux for sync and drift detection
  - CI Engine: Tekton Pipelines (cluster or namespace-scoped)
  - Artifact Registry: OCI registry (Harbor, GCR, ECR, ACR)
  - Secrets: HashiCorp Vault via CSI + K/V
  - Policy: OPA Gatekeeper or Kyverno
  - Admission: ImagePolicyWebhook, PodSecurityAdmission
  - Service Mesh: Istio/Linkerd for traffic controls and telemetry
  - Observability: Prometheus, OpenTelemetry Collector, Loki/Elasticsearch, Jaeger
  - Workload Autoscaler: KEDA for event-based scaling

Namespaces & Isolation

- `platform-system` — GitOps, Observability, Policy, Registry connectors
- `ci-cd` — Tekton controllers and build infrastructure
- `infra-<env>` — infra controllers per cloud (cluster-autoscaler, cloud-provider IAM)
- `apps-ephemeral-*` — ephemeral test environments per PR
- `prod` — production workloads with strict PSP and network policies

Identity & Access

- Short-lived service accounts via OIDC (OIDC federation to IdP)
- Pod identity via projected tokens and Vault Agent
- RBAC: least-privilege per team via GitOps-managed RBAC manifests

Build & Runtime Security

- Admission policies to enforce signed artifacts and SBOM presence
- Image scanning on push + admission-time allow/deny
- NetworkPolicies to minimize blast radius

Scaling & Multi-cloud

- Use cluster-provisioning templates (Cluster API) and central management
- Cross-cluster service discovery and global ingress (Gateway API)

Operational Patterns

- Platform upgrades: GitOps PR + canary for platform components
- Day-2: runbook CRs stored in Git and surfaced in developer portal

Appendix

- Reference manifest examples and CRD snippets are provided in `.ci/manifests/`.