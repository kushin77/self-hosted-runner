Elite Prompt: Autonomous 4-Layer CI/CD System (Self-Hosted Runner Edition)

You are a FAANG-level DevOps architect designing a production-grade autonomous CI/CD platform that uses self-hosted ephemeral runners.

Mission
Design a 4-layer CI/CD architecture that automatically promotes code to production once quality and safety gates are satisfied. Focus on deterministic builds, ephemeral self-hosted runners, and safe autonomous promotion with a confidence scoring mechanism.

Goals
- Fully automated production deployment
- Deterministic builds and hermetic environments
- Maximum developer velocity with safe auto-promotion
- Enterprise-grade security, policy enforcement, and observability
- Kubernetes-native, GitOps-driven, multi-cloud compatible
- Runner lifecycle controlled (bootstrap, register, run, destroy)

System Constraints (Self-hosted runner specifics)
- Runners must be ephemeral and destroyed after jobs
- Runner bootstrapping is repo-driven (pull on boot)
- Runners cannot have direct unrestricted access to production; use deployment gateway/GitOps controller
- Every produced artifact must be signed (cosign / sigstore) and have SBOM
- Policy-as-code (OPA/Kyverno) must be enforced at build and GitOps time

Layers

LAYER 1 — Commit Intelligence (Fast Path)
Trigger: every commit / MR / scheduled build
Runs on ephemeral runner pods/VMs
Actions:
- change-impact analysis (Bazel-style build graph)
- compute affected services/modules
- run incremental build of affected modules
- run lint, unit tests, and SAST (Semgrep)
- secret detection and policy checks
Outputs:
- set of affected artifacts
- test + lint + sast pass/fail
- incremental build artifacts (cached)
- confidence inputs (pass_rate, historical_stability, security_score)

LAYER 2 — Artifact & Environment Build
Trigger: after Layer 1 success for affected artifacts
Environment: hermetic build (BuildKit, Kaniko, Bazel remote exec)
Actions:
- full reproducible artifact build (container images, infra modules)
- SBOM generation (syft)
- vulnerability scan on build artifacts (trivy)
- sign artifacts with cosign (store signature + provenance)
- push to immutable, access-controlled registry
Outputs:
- signed artifact + SBOM + provenance assertions

LAYER 3 — Autonomous Validation (Deep Path)
Trigger: asynchronously after artifacts are produced
Environment: ephemeral ephemeral namespaces / preview clusters
Actions:
- deploy artifacts to ephemeral environment using GitOps or ephemeral k8s namespace
- run integration tests, contract tests, infra validation
- performance benchmarks & smoke tests
- chaos tests (optional based on risk policy)
- security validation (runtime scanning, policy checks)
Outputs:
- validation report (pass/fail per test category)
- validation metrics for confidence scoring

LAYER 4 — Progressive Production Deployment
Trigger: on successful validation and confidence score check
Mechanism: Promote via GitOps controller (ArgoCD/Flux). The runner never directly pushes to production cluster.
Strategies:
- Canary + automated telemetry analysis
- Blue/Green with traffic switch + monitoring window
- Automated rollback if anomalies detected
- Gradual promotion rules defined by SLOs
Outputs:
- deployment proposal (Git PR for GitOps controller) or automated merge if confidence is high
- telemetry and rollback events

Autonomous Promotion — Deployment Confidence Score
Compute confidence_score in [0,1] using weighted inputs:
- tests_pass_rate (0-1)
- historical_stability (0-1)
- error_budget_remaining (0-1)
- security_score (0-1)
- deployment_similarity (0-1)

confidence_score = w1*tests_pass_rate + w2*historical_stability + w3*error_budget_remaining + w4*security_score + w5*deployment_similarity

Policy: Promote automatically if confidence_score >= 0.92 and no critical security violations.

Safety & Guardrails
- Runner isolation: ephemeral pods/Firecracker microVMs
- No secrets persisted on runners; secrets injection from Vault with short TTLs
- Artifact signing mandatory; verify signature before deployment
- Deployment gateway / GitOps controller mediates production changes
- OPA policies enforced at build-time and admission time
- Human approval tier for high-risk deployments (policy-driven)

Observability & Telemetry
- Full metrics, logs, traces for pipeline and runners (OpenTelemetry)
- Real-time anomaly detection to trigger rollback
- Dashboard: DORA metrics, pipeline reliability, runner health, cost

Deliverables Requested
1. Full system architecture diagram
2. Reference Kubernetes architecture for runners and ephemeral envs
3. Example pipeline YAML (Fast + Deep paths + promotion logic)
4. Artifact promotion workflow (GitOps PR or signed merge)
5. Security control framework (policies & enforcement points)
6. Observability model (metrics/alerts)
7. Production rollback strategy + automation

If you produce code, also include:
- Bootstrap scripts for ephemeral self-hosted runner (clone, verify, register)
- Example cosign signing + verification steps
- Example OPA/Kyverno policy snippets

Operational Notes
- For self-hosted runners, add runner identity (id, type, region, capabilities)
- Segment runner pools by trust boundary (release vs dev vs public)
- Use a deployment gateway to prevent CI from directly changing production

Finish by producing: architecture diagram (text SVG/mermaid), `ci/4-layer.yml` example, `cicd-runner-platform/` skeleton with bootstrap script, `docs/4-layer-design.md`, and a ready-to-run prompt that can be fed to an internal LLM to auto-generate a full implementation.
