# CI/CD Runner Platform Architecture

## Overview

This repository defines a self-provisioning, self-healing CI/CD runner platform for GitHub Actions. Runners boot from cloud-init/user-data, clone this repo, and automatically:

- **Bootstrap** themselves with dependencies
- **Secure** themselves with policies and security isolation
- **Register** with GitHub or GitHub Enterprise
- **Update** themselves when new versions are available
- **Heal** themselves when health checks fail
- **Destroy** themselves safely when decommissioned

## Core Principles

1. **Never trust the workspace after a job completes** — All workspaces are ephemeral and cleaned/destroyed after job execution.
2. **Immutable infrastructure** — Runners are stateless; state comes from Git.
3. **Full observability** — Every action is instrumented with metrics, logs, and traces.
4. **Defense in depth** — Multiple layers of security isolation (containers, policies, secrets, signing).
5. **Autonomous operations** — Runners self-heal and auto-update without manual intervention.

## Directory Structure

```
cicd-runner-platform/
├── bootstrap/              # Self-provisioning on first boot
├── runner/                 # Runner installation and registration
├── runtime/                # Container, Kubernetes, sandbox configs
├── pipeline-executors/     # Job type handlers (build, test, security, deploy)
├── security/               # Policies, SBOM, artifact signing
├── observability/          # Metrics, logging, tracing
├── self-update/            # Auto-update logic and rollback
├── config/                 # Configuration and feature flags
├── scripts/                # Health checks, cleanup, destruction
└── docs/                   # Architecture and guides
```

## Lifecycle

### Bootstrap Phase

When a machine boots with cloud-init pointing to this repo:

1. `bootstrap.sh` runs (Linux) or `bootstrap.ps1` (Windows)
2. Host security verification
3. Dependency installation
4. Runner installation
5. Runner registration with GitHub
6. Systemd service configuration
7. Observability agent setup
8. Health checks enabled

### Job Execution Phase

For each job:

1. Pull job from GitHub Actions API
2. Create ephemeral workspace (temp volume, isolated network)
3. Execute job in sandboxed container (docker, gvisor, or firecracker)
4. Collect artifacts, logs, traces
5. Generate SBOM and sign artifacts
6. Clean workspace completely (immutable: "never trust")
7. Mark job as complete

### Self-Update Phase

Continuously (controlled by `UPDATE_INTERVAL`):

1. Check GitHub Actions runner releases
2. Compare installed version with latest
3. If update available and NO jobs running:
   - Stop runner gracefully
   - Download and extract new runner
   - Backup current version
   - Restart runner
   - Health check; rollback if failed
   - Upload success metric

### Self-Healing Phase

Periodically (controlled by health check daemon):

1. Check process status, disk, memory, network, Docker
2. If any check fails (score > 2):
   - Attempt restart
   - If restart succeeds → return to normal
   - If restart fails → quarantine and signal for destruction
3. Cleanup old containers and job artifacts
4. Report health to observability stack

### Destruction Phase

When runner is decommissioned (manual or auto):

1. Graceful shutdown
2. Drain pending jobs
3. Unregister from GitHub
4. Kill remaining processes
5. Securely wipe credentials and sensitive files (shred)
6. Remove Docker artifacts
7. Delete runner user
8. Remove systemd service
9. Log destruction in audit trail
10. Optional: halt the machine

## Security Model

### Workspace Isolation

- **Ephemeral workspaces**: Temp directories created per job, destroyed after
- **Immutable**: No state persists between jobs
- **Network isolation**: gVisor or Firecracker sandboxes prevent host access
- **Readonly rootfs**: Filesystem hardened against modification

### Secret Management

- Secrets injected at runtime via GitHub Actions API
- Never stored on disk
- Vault integration for dynamic secrets
- Automatic rotation
- Audit logging for all secret access

### Artifact Security

- All artifacts signed with Cosign (asymmetric)
- SBOMs generated and stored
- Vulnerability scanning at build and admission time
- Signatures verified before production deployment
- Attestations stored in transparency logs (rekor)

### Policy Enforcement

- OPA/Gatekeeper policies in `security/policy/`
- Enforce signed artifacts, SBOM presence, resource limits
- Prevent privileged containers, root filesystem writable
- Network policy isolation
- Compliance checks (SOC2, PCI-DSS, HIPAA)

## Observability

### Metrics

- Runner health (process, disk, memory, network)
- Job execution time, result, artifact info
- Resource usage per job
- Update/rollback events
- Exported to Prometheus

### Logs

- All events logged to stdout/stderr and journald
- Fluent Bit ships logs to Loki or OpenSearch
- Structured JSON logging for easy parsing
- Retention: 90 days (configurable)

### Traces

- OpenTelemetry integration
- Distributed tracing of job execution
- Link traces to commits, artifacts, security scans
- Root cause analysis on failure
- Exported to Tempo or Jaeger

## Configuration

See `config/runner-env.yaml` for all environment variables.

Key settings:

- `EPHEMERAL_WORKSPACE`: Enable workspace destruction per job
- `ENABLE_AUTO_HEALING`: Enable self-healing daemon
- `AUTO_UPDATE_RUNNER`: Enable automatic updates
- `REQUIRE_SIGNED_ARTIFACTS`: Enforce artifact signing
- `SANDBOX_TYPE`: docker, gvisor, or firecracker

## Feature Flags

See `config/feature-flags.yaml` for rollout controls.

Enable/disable features and control rollout percentage without redeployment.

## Advanced: Runner Control Plane

For multi-runner setups, add a runner orchestrator:

- Centralized job scheduling
- Runner health monitoring
- Auto-provisioning of new runners based on queue depth
- Cost optimization (scale down unused runners)
- Disaster recovery coordination

See `docs/runner-control-plane.md` for architecture.

## Getting Started

### Docker

```bash
docker build -f cicd-runner-platform/runtime/docker/Dockerfile.runner -t runner:latest .
docker run --rm -e RUNNER_TOKEN=xyz -e RUNNER_URL=https://github.com runner:latest
```

### Kubernetes

```bash
kubectl apply -f cicd-runner-platform/runtime/kubernetes/runner-deployment.yaml
```

See `docs/runner-lifecycle.md` and `docs/security-model.md` for detailed guides.
