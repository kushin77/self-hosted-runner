# Scripts Registry & Catalog

**Last Updated**: March 7, 2026  
**Status**: 📚 Complete Script Inventory (172 scripts across 276 files)  
**Purpose**: Discover and understand what all scripts do, where they live, and how to use them

---

## Quick Navigation

- [Search Scripts](#search-scripts-programmatically) - Find scripts quickly
- [Scripts by Category](#scripts-by-category) - 9 main categories
- [Scripts by Function](#scripts-by-function) - What they accomplish
- [Most Critical Scripts](#most-critical-scripts) - High-impact, commonly-used
- [Script Dependencies](#script-dependencies) - Which scripts call which
- [Common Tasks](#common-tasks-and-scripts) - Task → script mapping

---

## Search Scripts Programmatically

### Quick Shell Commands

```bash
# Find all executable scripts
find scripts -type f -executable | sort

# Search by name pattern
find scripts -type f -name "*terraform*"
find scripts -type f -name "*deploy*"
find scripts -type f -name "*monitor*"

# Show script count by directory
find scripts -type f -executable | sed 's|/[^/]*$||' | sort | uniq -c

# Show script with help/description
grep -h "^# Purpose\|^# Description" scripts/**/*.sh | head -20

# Find scripts that are called by workflows
grep -rh "\.sh" .github/workflows/*.yml | grep -oE 'scripts/[a-z-_/]*\.sh' | sort -u

# Find which scripts call other scripts
grep -rh "source\|bash\|\. " scripts/**/*.sh | grep "scripts/" | head -10

# Count lines of code per script (complexity)
find scripts -type f -name "*.sh" -exec wc -l {} + | sort -rn | head -20
```

### Use the Script Discovery Tool

```bash
# Full script registry
bash scripts/audit-scripts.sh --full

# List scripts by category
bash scripts/audit-scripts.sh --category automation

# Find scripts by function (deploy, monitor, validate)
bash scripts/audit-scripts.sh --function deploy

# Show critical scripts (high usage, dependencies)
bash scripts/audit-scripts.sh --critical

# Export as JSON
bash scripts/audit-scripts.sh --json > scripts.json

# Show script dependencies
bash scripts/audit-scripts.sh --dependencies

# Find unused scripts
bash scripts/audit-scripts.sh --unused
```

---

## Scripts by Category

### **1. Terraform & Infrastructure** (28 scripts)
Terraform planning, applying, validation, drift detection

**Key Scripts:**
```
scripts/automation/terraform-phase2.sh
  → Main orchestration for Phase 2 infrastructure
  → Calls: terraform init, plan, apply
  → Used by: terraform-auto-apply.yml, terraform-apply.yml

scripts/automation/pmo/validate-pre-deployment.sh
  → Validates infrastructure before deployment
  → Checks: resource health, quota availability, security groups
  → Used by: cloud-ops-bootstrap.yml

scripts/automation/pmo/drift-detector.sh
  → Detects infrastructure drift
  → Compares: actual state vs desired state
  → Used by: terraform-phase2-drift-detection.yml

scripts/automation/pmo/deploy-p2-production.sh
  → Deploy Phase 2 to production
  → Multi-stage: plan → validate → apply → verify
  → Used by: Manual dispatch from ops
```

**When to Use:**
- Planning terraform changes: Use `terraform-phase2.sh` 
- Checking for drift: Use `drift-detector.sh`
- Full deployment: Use `deploy-p2-production.sh`
- Pre-deployment validation: Use `validate-pre-deployment.sh`

---

### **2. Deployment & Release** (22 scripts)
Canary deployments, progressive rollouts, artifact management

**Key Scripts:**
```
scripts/automation/pmo/deploy-full-stack.sh
  → Deploy entire stack (terraform + apps)
  → Options: --dry-run, --rolling, --canary
  → Used by: progressive-rollout.yml, canary-deployment.yml

scripts/automation/pmo/spot_interruption_handler.sh
  → Handle AWS Spot interruption gracefully
  → Actions: Drain, reschedule, failover
  → Used by: (auto-triggered on Spot event)

scripts/automation/mirror-release-artifacts.sh
  → Mirror release artifacts to multiple registries
  → Options: --docker, --helm, --all
  → Used by: mirror-release-artifacts.yml
```

**When to Use:**
- Full stack deployment: Use `deploy-full-stack.sh --rolling`
- Handling spot interruptions: Use `spot_interruption_handler.sh`
- Mirroring artifacts: Use `mirror-release-artifacts.sh`

---

### **3. Runner Management** (18 scripts)
Provisioning, health checking, self-healing, lifecycle

**Key Scripts:**
```
scripts/automation/pmo/runner_health_monitor.sh
  → Monitor runner health (CPU, memory, disk, network)
  → Output: JSON of health metrics
  → Used by: automation-health-validator.yml

scripts/automation/pmo/ephemeral-workspace-manager.sh
  → Manage ephemeral runner workspaces
  → Actions: create, cleanup, rotate
  → Used by: runner cleanup workflows

scripts/provision-runner.sh
  → Provision new self-hosted runner
  → Options: --label LAB, --pool POOL, --count N
  → Used by: agent-provision-on-issue-comment.yml

scripts/legacy-node-cleanup.sh
  → Clean up legacy/deprecated runner nodes
  → Safe: Drains jobs first before terminating
  → Used by: legacy-node-cleanup.yml
```

**When to Use:**
- Check runner health: Use `runner_health_monitor.sh`
- Provision new runners: Use `provision-runner.sh`
- Clean up old runners: Use `legacy-node-cleanup.sh`

---

### **4. Monitoring & Observability** (16 scripts)
Metrics collection, logging, alerting, health checks

**Key Scripts:**
```
scripts/monitoring/collect-metrics.sh
  → Collect Prometheus metrics from all runners
  → Output: Prometheus format
  → Used by: observability-monitor.yml

scripts/monitoring/send-alerts.sh
  → Send alerts to Slack/PagerDuty/Email
  → Template: Alert message template
  → Used by: remediation workflows

scripts/automation/pmo/otel-tracer.sh
  → OpenTelemetry tracing for workflows
  → Output: Trace spans to observability backend
  → Used by: All critical workflows

scripts/automation/pmo/prometheus/run_e2e_ephemeral_test.sh
  → Run end-to-end tests in ephemeral environment
  → Metrics: Collects test results as metrics
  → Used by: e2e-validate.yml
```

**When to Use:**
- Collecting metrics: Use `collect-metrics.sh`
- Sending alerts: Use `send-alerts.sh`
- Tracing workflows: Use `otel-tracer.sh`
- Running e2e tests: Use `run_e2e_ephemeral_test.sh`

---

### **5. Automation & Orchestration** (24 scripts)
Auto-trigger, workflow dispatch, remediation, scheduling

**Key Scripts:**
```
scripts/automation/auto-apply-on-approval.sh
  → Auto-apply terraform/changes when PR approved
  → Checks: approval + required reviews
  → Used by: issue-tracker-automation.yml

scripts/automation/auto-pr-merge.sh
  → Auto-merge qualifying PRs
  → Checks: all tests pass, reviews approved, no conflicts
  → Used by: auto-merge-cron.yml

scripts/automation/auto-merge-post-validation.sh
  → Merge PR after validation workflow succeeds
  → Verification: checks workflow status
  → Used by: validation completion workflows

scripts/automation/pmo/job-cancellation-handler.sh
  → Cancel in-progress jobs based on rules
  → Rules: timeout, resource limits, priority
  → Used by: job failure handling
```

**When to Use:**
- Auto-apply on approval: Use `auto-apply-on-approval.sh`
- Auto-merge PRs: Use `auto-pr-merge.sh`
- Merge after validation: Use `auto-merge-post-validation.sh`
- Cancel stuck jobs: Use `job-cancellation-handler.sh`

---

### **6. Security & Secrets** (14 scripts)
Secret rotation, key management, credential provisioning

**Key Scripts:**
```
scripts/setup-automation-secrets.sh
  → Interactive setup of GitHub automation secrets
  → Generates: SSH keys, deploy tokens, management tokens
  → Used by: Initial setup (manual)

scripts/setup-automation-secrets-direct.sh
  → Fast non-interactive secret setup
  → Used by: CI/CD setup workflows

scripts/secret-rotation-coordinator.sh
  → Orchestrate credential rotation
  → Actions: Generate new creds, update in secret stores, revoke old
  → Used by: secret-rotation-coordinator.yml

scripts/vault_store_webhook.sh
  → Store webhook secrets in Vault
  → Used by: Notification workflows
```

**When to Use:**
- Initial setup: Use `setup-automation-secrets.sh`
- Rotate credentials: Use `secret-rotation-coordinator.sh`
- Store webhooks: Use `vault_store_webhook.sh`

---

### **7. Validation & Testing** (19 scripts)
Test execution, manifest validation, smoke tests, e2e tests

**Key Scripts:**
```
scripts/validate/validate-manifests.sh
  → Validate Kubernetes manifests
  → Checks: syntax, schema, resource health
  → Used by: validate-manifests.yml

scripts/validate/lint-workflows.sh
  → Lint GitHub Actions workflows
  → Checks: syntax, naming conventions,best practices
  → Used by: workflow validation workflows

scripts/test-e2e.sh
  → Run end-to-end integration tests
  → Options: --quick, --full, --stress
  → Used by: e2e-validate.yml

scripts/automation/pmo/runner_pytest_hygiene.sh
  → Check pytest test hygiene
  → Warns: inefficient tests, missing fixtures
  → Used by: CI/CD quality gates
```

**When to Use:**
- Validate k8s manifests: Use `validate-manifests.sh`
- Lint workflows: Use `lint-workflows.sh`
- Run e2e tests: Use `test-e2e.sh`
- Check test quality: Use `runner_pytest_hygiene.sh`

---

### **8. Utility & Helpers** (21 scripts)
Logging, error handling, common functions, helpers

**Key Scripts:**
```
scripts/ci/utils.sh
  → Common CI/CD utility functions
  → Functions: retry, wait_for, check_health, etc.
  → Source in: Any CI workflow

scripts/lib/logging.sh
  → Structured logging functions
  → Functions: log_info, log_error, log_debug
  → Source in: All scripts that need logging

scripts/lib/error-handler.sh
  → Centralized error handling
  → Catches: Exit codes, signals, cleanup
  → Source in: All critical scripts

scripts/audit-secrets.sh
  → Audit and discover all secrets
  → Modes: --full, --json, --validate, --search
  → Used by: Security audits

scripts/audit-scripts.sh
  → Audit and discover all scripts
  → Modes: --full, --json, --dependencies
  → Used by: Script discovery

scripts/audit-workflows.sh
  → Audit and discover all workflows
  → Modes: --full, --json, --category
  → Used by: Workflow discovery
```

**When to Use:**
- In any shell script: Source `scripts/lib/logging.sh`
- Retry logic needed: Source `scripts/ci/utils.sh` and use `retry`
- Error handling needed: Source `scripts/lib/error-handler.sh`

---

### **9. Infrastructure & VM Management** (18 scripts)
VM provisioning, Docker, Ansible, infrastructure setup

**Key Scripts:**
```
scripts/automation/legacy/install_deploy_key.sh
  → Install SSH deploy key on runners
  → Used by: SSH provisioning workflows

scripts/automation/ansible-runner.sh
  → Execute Ansible playbooks
  → Options: --inventory, --playbook, --tags
  → Used by: Ansible automation workflows

scripts/pmo/docker-build.sh
  → Build Docker images with caching
  → Options: --tag, --push, --registry
  → Used by: ci-images.yml

scripts/pmo/push-image-to-registry.sh
  → Push Docker images to registries
  → Registries: Docker Hub, ECR, GCR
  → Used by: Image publishing workflows
```

**When to Use:**
- Install SSH keys: Use `install_deploy_key.sh`
- Run Ansible: Use `ansible-runner.sh`
- Build Docker images: Use `docker-build.sh`
- Push images: Use `push-image-to-registry.sh`

---

## Most Critical Scripts

**High-impact, frequently-used scripts (must function correctly):**

| Script | Category | Usage | Failure Impact |
|--------|----------|-------|-----------------|
| `scripts/automation/terraform-phase2.sh` | Infrastructure | terraform-auto-apply.yml | 🔴 CRITICAL - Blocks deployments |
| `scripts/automation/pmo/runner_health_monitor.sh` | Runner Mgmt | automation-health-validator.yml | 🔴 CRITICAL - Hides failures |
| `scripts/audit-secrets.sh` | Discovery | Security audits, troubleshooting | 🟠 HIGH - Debugging blocked |
| `scripts/automation/auto-apply-on-approval.sh` | Automation | PR approval workflows | 🟠 HIGH - Manual intervention needed |
| `scripts/automation/pmo/deploy-full-stack.sh` | Deployment | Progressive rollouts | 🟠 HIGH - Deployments blocked |
| `scripts/automation/pmo/drift-detector.sh` | Infrastructure | Drift detection | 🟠 HIGH - Unknown state |
| `scripts/validate/validate-manifests.sh` | Testing | Manifest validation | 🟡 MEDIUM - Bad manifests deployed |
| `scripts/automation/secret-rotation-coordinator.sh` | Security | Credential rotation | 🟡 MEDIUM - Credentials expire |

---

## Script Dependencies

### **Dependency Chain 1: Infrastructure Deployment**
```
cloud-ops-bootstrap.yml
  └─→ scripts/automation/terraform-phase2.sh
      ├─→ scripts/ci/utils.sh (retry logic)
      ├─→ scripts/lib/logging.sh (structured logging)
      └─→ scripts/lib/error-handler.sh (error handling)
          └─→ scripts/automation/pmo/validate-pre-deployment.sh
              └─→ scripts/ci/utils.sh
          └─→ scripts/automation/pmo/deploy-full-stack.sh
```

### **Dependency Chain 2: Runner Health**
```
automation-health-validator.yml
  └─→ scripts/automation/pmo/runner_health_monitor.sh
      └─→ scripts/monitoring/collect-metrics.sh
          └─→ scripts/lib/logging.sh
      └─→ [If unhealthy] scripts/automation/pmo/ephemeral-workspace-manager.sh
      └─→ [If very unhealthy] scripts/legacy-node-cleanup.sh
```

### **Dependency Chain 3: PR Workflow**
```
PR Created
  └─→ validate-manifests.yml
      └─→ scripts/validate/validate-manifests.sh
          └─→ scripts/ci/utils.sh
  └─→ [If approved + tests pass]
      └─→ scripts/automation/auto-apply-on-approval.sh
          └─→ scripts/automation/terraform-phase2.sh
```

---

## Common Tasks and Scripts

### "I need to deploy something"
**Task:** Deploy terraform changes to AWS

1. Check permissions: Verify `AWS_OIDC_ROLE_ARN` is set
2. Plan changes: `scripts/automation/terraform-phase2.sh --plan`
3. Review plan: Check output in PR comment
4. Approve: Approve PR
5. Apply: Auto-apply triggers OR manually: `scripts/automation/auto-apply-on-approval.sh`

**Related:**
- Canary deployment: Use `scripts/automation/pmo/deploy-full-stack.sh --canary`
- Safe deployment: Use `scripts/automation/pmo/validate-pre-deployment.sh` first
- Full stack: Use `scripts/automation/pmo/deploy-full-stack.sh --rolling`

---

### "My runners are failing"
**Task:** Diagnose and fix unhealthy runners

1. Check health: `scripts/automation/pmo/runner_health_monitor.sh`
2. Analyze metrics: Check CPU, memory, disk, network
3. Auto-heal: `automation-health-validator.yml` triggers `ephemeral-workspace-manager.sh`
4. If still failing: `scripts/legacy-node-cleanup.sh` to remove bad node
5. Provision new: `scripts/provision-runner.sh --label self-hosted`

**Related:**
- Monitor continuously: `automation-health-validator.yml` (every 6 hours)
- Manual health check: `scripts/automation/pmo/runner_health_monitor.sh`
- Workspace cleanup: `scripts/automation/pmo/ephemeral-workspace-manager.sh`

---

### "I need to rotate secrets/credentials"
**Task:** Safely rotate all credentials

1. Plan rotation: Review `scripts/secret-rotation-coordinator.sh`
2. Execute: Trigger `secret-rotation-coordinator.yml`
   - If Vault-backed: Vault auto-rotates secret IDs (24h)
   - If GitHub secrets: Manually rotate via `gh secret set`
   - If GSM: Manually rotate via `gcloud secrets`
3. Verify: Check old creds revoked, new creds active

**Related:**
- GitHub secret setup: `scripts/setup-automation-secrets-direct.sh`
- Vault integration: `scripts/vault_store_webhook.sh`
- Audit secrets: `scripts/audit-secrets.sh`

---

### "I need to release something to production"
**Task:** Safe, progressive release

1. Create release: Tag in GitHub
2. Build artifacts: `ci-images.yml` runs `scripts/pmo/docker-build.sh`
3. Sign artifacts: `slsa-provenance-release.yml` signs
4. Canary: `scripts/automation/pmo/deploy-full-stack.sh --canary` (10%)
5. Monitor: `scripts/automation/pmo/runner_health_monitor.sh` checks health
6. Progressive: Auto-escalate to 50% then 100%
7. Rollback: `scripts/automation/pmo/deploy-full-stack.sh --rollback` if needed

**Related:**
- Mirror artifacts: `scripts/mirror-release-artifacts.sh`
- Push to registry: `scripts/pmo/push-image-to-registry.sh`
- Progressive rollout: `scripts/automation/pmo/deploy-full-stack.sh --rolling`

---

## Script Structure & Conventions

### Common Script Header
```bash
#!/bin/bash
# Purpose: Brief description
# Usage: ./script-name.sh [options]
# Example: ./script-name.sh --dry-run --verbose
#
# Options:
#   --help           Show this help message
#   --dry-run        Show what would be done without doing it
#   --verbose        Enable debug logging
#   --timeout N      Timeout in seconds

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Source utilities
source "$(dirname "$0")/../ci/utils.sh"
source "$(dirname "$0")/../lib/logging.sh"
source "$(dirname "$0")/../lib/error-handler.sh"

# Main logic
main() {
  log_info "Starting script..."
  # Implementation
  log_info "Complete!"
}

main "$@"
```

### Common Functions (in `scripts/ci/utils.sh`)
```bash
# Retry with exponential backoff
retry N COMMAND

# Wait for condition with timeout
wait_for CONDITION --timeout 300

# Check service health
check_health SERVICE

# Run command with logging
run_cmd DESCRIPTION COMMAND

# Parse command-line arguments
parse_args "$@"
```

---

## Quick Reference: Script Locations

```
scripts/
├── audit-*.sh                   # Discovery tools (secrets, workflows, scripts)
├── setup-automation-*.sh        # Initial setup scripts
├── ci/
│   └── utils.sh                 # Common CI utilities
├── lib/
│   ├── logging.sh               # Logging functions
│   └── error-handler.sh         # Error handling
├── automation/
│   ├── terraform-phase2.sh      # Main terraform orchestration
│   ├── auto-*.sh                # Automation workflows
│   ├── pmo/                     # Phase Management Office scripts
│   │   ├── deploy-*.sh          # Deployment scripts
│   │   ├── runner_*.sh          # Runner management
│   │   └── .../                 # More scripts
│   ├── ci/
│   └── legacy/
├── monitoring/
│   ├── collect-metrics.sh
│   └── send-alerts.sh
├── validate/
│   ├── validate-manifests.sh
│   └── lint-workflows.sh
├── test-*.sh                    # Testing scripts
└── minio/                       # MinIO artifact storage
    ├── upload.sh
    └── download.sh
```

---

## Finding Help for a Script

Each script should include:
```bash
# At the top:
# Purpose: What it does
# Usage: How to use it
# Example: Real example

# Or run:
./script-name.sh --help
```

If a script is missing help:
```bash
head -20 scripts/path/script.sh  # Read purpose/usage at top
grep -A 5 "^main()" scripts/path/script.sh  # Find main logic
grep "^function" scripts/path/script.sh  # List available functions
```

---

## Related Documentation

- **[WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md)** — Which workflows call which scripts
- **[SECRETS_INDEX.md](SECRETS_INDEX.md)** — What secrets scripts access
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Adding new scripts
- **[DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md)** — Installing scripts

---

## Quick Stats

| Metric | Count |
|--------|-------|
| **Total Script Files** | 276 |
| **Executable Scripts** | 172 |
| **Script Directories** | 12 |
| **Categories** | 9 |
| **Discovery Scripts** | 3 (@audit-*.sh) |

---

*Last Updated: March 7, 2026*  
*Maintained by: DevOps & Automation Team*  
*Next Review: June 7, 2026*
