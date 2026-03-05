# CI/CD Self-Provisioning Runner Platform

> Enterprise-grade, autonomous CI/CD runner that bootstraps, secures, self-heals, and destroys itself. FAANG-level DevOps architecture.

## Features

- ✅ **Self-Bootstrapping** — Runs on any cloud from cloud-init in < 5 minutes
- ✅ **Self-Securing** — Ephemeral workspaces, sandbox isolation, artifact signing, policy enforcement
- ✅ **Self-Registering** — Automatic GitHub Actions registration with metadata
- ✅ **Self-Updating** — Hourly update checks with automatic rollback on failure
- ✅ **Self-Healing** — Health daemon quarantines unhealthy runners and triggers recovery
- ✅ **Self-Destroying** — Safe unregistration, secure credential wipe (shred 10-pass), audit trail
- ✅ **Full Observability** — Prometheus metrics, Loki logs, OpenTelemetry traces
- ✅ **Enterprise Security** — OPA/Gatekeeper policies, signed artifacts, SBOM generation, compliance (SOC2/PCI/HIPAA)
- ✅ **Multi-Platform** — Linux (Ubuntu/CentOS), Windows, Kubernetes, multi-cloud (AWS/GCP/Azure)

## Quick Start

### Linux (EC2, GCP Compute, Azure VMs)

```bash
#!/usr/bin/env bash
# cloud-init user-data or manual bootstrap

git clone https://github.com/YOUR_ORG/self-hosted-runner /opt/runner-platform
cd /opt/runner-platform/bootstrap

export RUNNER_TOKEN=ghr_xxxxxxxxxxxxx
export RUNNER_URL=https://github.com
export RUNNER_LABELS=linux,self-hosted,docker

sudo bash bootstrap.sh
```

### Windows (EC2, Azure)

```powershell
# PowerShell (run as Administrator)
$RUNNER_TOKEN = "ghr_xxxxxxxxxxxxx"
$RUNNER_URL = "https://github.com"
$RUNNER_LABELS = "windows,self-hosted"

Set-ExecutionPolicy Bypass -Scope Process -Force
.\bootstrap.ps1
```

### Kubernetes

```bash
kubectl apply -f cicd-runner-platform/runtime/kubernetes/runner-deployment.yaml
```

## Architecture (4-Tier)

```
LAYER 1: Commit Intelligence
├─ Dependency graph analysis
├─ Change impact analysis
├─ Linting & unit tests
├─ SAST & secret scanning
└─ Policy enforcement → affected services list

LAYER 2: Artifact & Environment Build
├─ Hermetic builds (BuildKit)
├─ SBOM generation (Syft)
├─ Vulnerability scanning (Trivy)
├─ Artifact signing (Cosign)
└─ Push to OCI registry

LAYER 3: Autonomous Validation
├─ Ephemeral environment provisioning
├─ Integration/contract/perf/chaos tests
├─ Security validation
└─ SLO evaluation → promotion gate

LAYER 4: Progressive Production Deployment
├─ Canary/Blue-Green rollout (Argo Rollouts)
├─ Real-time telemetry analysis
├─ Anomaly detection
└─ Automated rollback or promote
```

## Directory Structure

```
cicd-runner-platform/
├── bootstrap/                  # Self-provisioning on first boot
│   ├── bootstrap.sh           # Linux entry point
│   ├── bootstrap.ps1          # Windows entry point
│   ├── verify-host.sh         # Security baseline checks
│   └── install-dependencies.sh
│
├── runner/                     # Installation & registration
│   ├── install-runner.sh
│   ├── register-runner.sh
│   └── update-runner.sh
│
├── pipeline-executors/         # Sandbox-isolated job handlers
│   ├── build-executor.sh       # SBOM + signing
│   ├── test-executor.sh        # Unit/integration/contract tests
│   ├── security-executor.sh    # SAST, scanning, policy checks
│   └── deploy-executor.sh      # Progressive rollout
│
├── security/                   # Policies & signing
│   ├── policy/
│   │   └── opa-policies.rego
│   ├── sbom/
│   │   └── generate-sbom.sh
│   └── artifact-signing/
│       └── cosign-sign.sh
│
├── observability/              # Metrics, logs, traces
│   ├── metrics-agent.yaml
│   ├── logging-agent.yaml
│   └── otel-config.yaml
│
├── self-update/                # Auto-update daemon
│   ├── update-checker.sh
│   └── rollback.sh
│
├── scripts/                    # Lifecycle scripts
│   ├── health-check.sh         # Self-healing daemon
│   ├── clean-runner.sh         # Workspace cleanup
│   └── destroy-runner.sh       # Safe destruction
│
├── config/                     # Configuration
│   ├── runner-env.yaml
│   ├── network-policy.yaml
│   └── feature-flags.yaml
│
├── runtime/                    # Container & K8s configs
│   ├── docker/
│   ├── kubernetes/
│   └── sandbox/
│
└── docs/                       # Documentation
    ├── architecture.md
    ├── runner-lifecycle.md
    ├── security-model.md
    ├── deployment-ec2.md
    ├── deployment-gcp.md
    └── deployment-azure.md
```

## Lifecycle Overview

```
Boot
  ↓
Cloud-init: clone repo & run bootstrap.sh
  ↓
Verify host security baseline
  ↓
Install dependencies (Docker, Cosign, Syft, etc.)
  ↓
Download & install GitHub Actions runner
  ↓
Register with GitHub
  ↓
Start systemd service
  ↓
Enable health-check daemon (5-min interval)
  ↓
Enable update-checker daemon (hourly)
  ↓
Wait for jobs...

For each job:
  ├─ Create ephemeral workspace
  ├─ Run in sandbox (Docker/gvisor/firecracker)
  ├─ Collect artifacts + SBOM + security scans
  ├─ Sign artifacts (Cosign)
  ├─ Report metrics to observability stack
  └─ SECURELY WIPE workspace (shred, not rm)

Background daemons:
  ├─ Health check: every 5 min (CPU, disk, memory, network, Docker)
  │   └─ On failure: attempt recovery → quarantine if failed
  ├─ Update checker: every hour
  │   └─ If update available & no jobs: update + rollback if needed
  └─ Metrics exporter: continuous to Prometheus

On destruction:
  ├─ Gracefully drain pending jobs
  ├─ Unregister from GitHub
  ├─ Securely wipe credentials (shred 10-pass)
  ├─ Remove all artifacts
  └─ Log to immutable audit trail
```

## Security Principles

### 1. Never Trust the Workspace

After each job, workspace is **destroyed** (not just cleaned):

```bash
# Ephemeral workspace per job
/tmp/job-${UUID}/

# After job completes:
- Files securely wiped (shred, not rm)
- Environment variables cleared
- Shell history cleared
- Docker containers destroyed
- Networks torn down
```

### 2. Defense in Depth

```
Layer 1: Sandbox isolation (Docker, gVisor, Firecracker)
Layer 2: Network policies (egress to GitHub/registries only)
Layer 3: Signed artifacts (Cosign)
Layer 4: SBOM generation (Syft)
Layer 5: Vulnerability scanning (Trivy)
Layer 6: Policy enforcement (OPA/Conftest)
Layer 7: Audit logging (immutable trail)
Layer 8: Runtime security (Falco, anomaly detection)
```

### 3. Automatic Remediation

```
Health check failure
  ↓
Attempt restart
  ↓
If restart succeeds → return to normal
If restart fails → quarantine
  ↓
Alert ops (email, Slack, PagerDuty)
```

## Configuration

Edit `config/runner-env.yaml` to customize behavior:

```yaml
# Enable ephemeral workspaces (destroy after job)
EPHEMERAL_WORKSPACE: true

# Enable artifact signing
REQUIRE_SIGNED_ARTIFACTS: true

# Enable auto-update
AUTO_UPDATE_RUNNER: true

# Enable auto-healing
ENABLE_AUTO_HEALING: true

# Sandbox type: docker, gvisor, firecracker
SANDBOX_TYPE: docker

# Health check interval (seconds)
HEALTH_CHECK_INTERVAL: 300

# Compliance modes
SOC2_COMPLIANCE_MODE: true
PCI_COMPLIANCE_MODE: false
HIPAA_COMPLIANCE_MODE: false
```

## Observability

### Metrics (Prometheus)

```
runner_status                    # 0=offline, 1=idle, 2=running
runner_job_duration_seconds      # job execution time
runner_job_result                # pass/fail counter
runner_health_score              # 0-6 (0=healthy)
runner_updates_total             # update attempts
runner_quarantine_total          # quarantine events
job_artifacts_signed_total       # artifacts signed
job_policy_violations_total      # policy violations
```

### Logs (Loki)

```
Bootstrap logs
Job execution logs (with secret masking)
Security scan results
Policy violations
Health check events
Update/rollback events
```

### Traces (Tempo)

```
Job execution span (parent)
  ├─ Step execution spans
  ├─ Artifact upload spans
  └─ Policy validation spans
```

## Deployment Guides

- [EC2 Deployment](docs/deployment-ec2.md) — Linux/Windows bootstrap via user-data
- [GCP Deployment](docs/deployment-gcp.md) — Compute Engine startup scripts
- [Azure Deployment](docs/deployment-azure.md) — Custom script extensions
- [Kubernetes Deployment](docs/deployment-k8s.md) — Pod lifecycle & network policies

## Integration Testing

```bash
# Unit tests
cd cicd-runner-platform
bash -x bootstrap/bootstrap.sh --dry-run

# Integration tests (on K3s cluster)
./tests/integration-test.sh

# Security tests
./tests/security-test.sh

# Cloud tests
./tests/cloud-test-ec2.sh
./tests/cloud-test-gcp.sh
./tests/cloud-test-azure.sh
```

## Troubleshooting

### Runner won't start

```bash
# Check bootstrap logs
tail -f /var/log/runner-bootstrap.log

# Verify dependencies
docker --version
git --version
cosign --version
syft --version

# Test connection to GitHub
curl -v https://api.github.com
```

### Health check failures

```bash
# Check health daemon
systemctl status runner-health-daemon.service
journalctl -u runner-health-daemon.service -f

# Run manual health check
bash scripts/health-check.sh

# Expected score:
# 0-1: Healthy
# 2-3: Degraded (auto-recovery attempted)
# ≥4: Unhealthy (quarantined)
```

### Update failures

```bash
# Check update daemon
systemctl status runner-update-checker.service
journalctl -u runner-update-checker.service -f

# Manual update (with rollback)
bash self-update/update-checker.sh

# Rollback to previous version
bash self-update/rollback.sh
```

### Workspace not cleaned

```bash
# Manual cleanup (safe)
bash scripts/clean-runner.sh

# Verify cleanup
ls -la /tmp/job-*          # should be empty
env | grep RUNNER_         # should be empty
history                    # should be empty
```

## Advanced: Runner Control Plane

For large deployments, add a centralized orchestrator:

```
Runner Control Plane
    ↓
  [Job Scheduler]
  [Health Monitoring]
  [Auto-provisioning]
  [Disaster Recovery]
    ↓
[Runner Pool] → [Runner Pod] → [Sandbox Container]
```

See [docs/runner-control-plane.md](docs/runner-control-plane.md) for architecture.

## Security Compliance

- **SOC2** — Audit logging, encryption, RBAC, incident response
- **PCI-DSS** — Network segmentation, secrets management, log retention
- **HIPAA** — Data encryption, access control, audit trails
- **FedRAMP** — Federal compliance with required controls

See [docs/security-model.md](docs/security-model.md) for threat model and controls.

## Contributing

1. Test all changes locally (unit + integration)
2. Update docs if adding features
3. Ensure policies pass OPA validation
4. Add security scanning for new dependencies
5. Follow shell script best practices (ShellCheck)

## Troubleshooting Runbooks

| Issue | Runbook |
|-------|---------|
| Runner offline | [Link](docs/runbooks/runner-offline.md) |
| Job failures | [Link](docs/runbooks/job-failures.md) |
| Credential leak | [Link](docs/runbooks/credential-leak.md) |
| Malicious code | [Link](docs/runbooks/malicious-code.md) |
| Disk full | [Link](docs/runbooks/disk-full.md) |
| Update failure | [Link](docs/runbooks/update-failure.md) |

## License

[Your License]

## Authors

DevOps Platform Team

## Support

- 📧 Email: devops@example.com
- 💬 Slack: #ci-cd-platform
- 🐛 Issues: [GitHub Issues](https://github.com/YOUR_ORG/self-hosted-runner/issues)
