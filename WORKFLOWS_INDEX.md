# Workflows Index & Catalog

**Last Updated**: March 7, 2026  
**Status**: 🔍 Complete Discovery Index (197 workflows)  
**Purpose**: Map all workflows by purpose, trigger, and relationships

---

## Quick Navigation

- [Search Workflows](#search-workflows-programmatically) - Discover workflows by keyword
- [Workflows by Category](#workflows-by-category) - 11 distinct categories
- [Workflows by Trigger Type](#workflows-by-trigger-type) - How they're invoked
- [Most Complex Workflows](#most-complex-workflows) - High-impact, multi-job
- [Workflow Dependencies](#workflow-dependencies) - Which workflows call which
- [Quick Reference](#quick-reference-commands) - Copy-paste commands

---

## Search Workflows Programmatically

### Quick Shell Commands

```bash
# Find workflows by name pattern
ls -1 .github/workflows/*.yml | grep "PATTERN"

# Find workflows by trigger type (push, schedule, dispatch, etc.)
grep -l "^on:" .github/workflows/*.yml | while read f; do
  echo "$(basename $f): $(grep -A 5 '^on:' $f | head -2)"
done | grep "schedule"

# Find workflows that use a specific secret
grep -l "secrets\.SECRET_NAME" .github/workflows/*.yml

# Count workflows by category (by prefix)
ls .github/workflows/*.yml | sed 's/.*\///; s/-[^-]*$//' | sort | uniq -c

# Find callable workflows (workflow_call)
grep -l "workflow_call" .github/workflows/*.yml | wc -l

# Find workflow_dispatch workflows (manual trigger)
grep -l "workflow_dispatch" .github/workflows/*.yml | head -10
```

### Use the Workflow Discovery Tool

```bash
# Full index with all workflows
bash scripts/audit-workflows.sh --full

# Search by category
bash scripts/audit-workflows.sh --category automation

# Search by trigger type
bash scripts/audit-workflows.sh --trigger dispatch

# Export as JSON (for automation)
bash scripts/audit-workflows.sh --json > workflows.json

# Show most complex workflows
bash scripts/audit-workflows.sh --complex
```

---

## Workflows by Category

**197 total workflows across 11 categories:**

### 1. **Automation & Self-Healing** (32 workflows)
Auto-trigger, auto-remediate, auto-close, auto-merge workflows that execute on events

**Key Workflows:**
| Workflow | Trigger | Purpose | Secrets |
|----------|---------|---------|---------|
| `automation-health-validator.yml` | Schedule | Validates automation system is operational | AWS_OIDC_ROLE_ARN, GCP_* |
| `auto-trigger-on-label.yml` | Issues | Triggers terraform-auto-apply when labeled | AWS_OIDC_ROLE_ARN |
| `auto-resolve-missing-secrets.yml` | Schedule | Auto-configure missing GitHub secrets | RUNNER_MGMT_TOKEN |
| `auto-merge-dependabot.yml` | PR | Auto-merge dependabot PRs | GITHUB_TOKEN |
| `auto-merge-cron.yml` | Schedule | Periodic auto-merge of qualifying PRs | GITHUB_TOKEN |
| `auto-remediate-deps.yml` | Workflow Dispatch | Fix dependency issues | GITHUB_TOKEN |
| `auto-ssh-key-provisioning.yml` | Issue Comment | Auto-provision SSH keys to runners | DEPLOY_SSH_KEY |
| `auto-run-on-ops.yml` | Issue Comment | Run workflows triggered from ops | GITHUB_TOKEN |

**Use Case:** When you need workflows to self-heal and respond to system states

---

### 2. **Infrastructure & Cloud Provisioning** (28 workflows)
Terraform, cloud resource management, infrastructure deployment

**Key Workflows:**
| Workflow | Trigger | Purpose | Infrastructure |
|----------|---------|---------|-----------------|
| `cloud-ops-bootstrap.yml` | Dispatch | Single-click provision ALL cloud resources | Terraform, AWS, GCP |
| `terraform-auto-apply.yml` | Label `terraform` | Auto-apply terraform changes on push | AWS OIDC, GSM secrets |
| `terraform-plan.yml` | Comment trigger | Plan terraform changes | AWS OIDC |
| `elasticache-apply-gsm.yml` | Dispatch | Deploy ElastiCache via GSM creds | AWS (via GSM) |
| `elasticache-apply-safe.yml` | Dispatch | Safe ElastiCache deployment | AWS OIDC |
| `terraform-phase2-drift-detection.yml` | Schedule | Detect infrastructure drift | AWS OIDC |
| `terraform-phase2-final-plan-apply.yml` | Dispatch | Final terraform apply | AWS OIDC |

**Use Case:** Managing AWS/GCP infrastructure with GitOps pattern

---

### 3. **CI/CD & Testing** (24 workflows)
Build, test, validation, e2e testing

**Key Workflows:**
| Workflow | Trigger | Purpose | Infrastructure |
|----------|---------|---------|-----------------|
| `e2e-validate.yml` | Push | End-to-end validation | MinIO, self-hosted |
| `validate-manifests.yml` | Push | Validate Kubernetes manifests | Self-hosted |
| `ci-images.yml` | Schedule | Build/push container images | Container registry |
| `secrets-scan.yml` | Push | Detect secrets in code | Detect-secrets |

**Use Case:** Automated testing on every push

---

### 4. **Runner Management** (18 workflows)
Runner provisioning, health checks, lifecycle management

**Key Workflows:**
| Workflow | Trigger | Purpose | Runner Impact |
|----------|---------|---------|---------------|
| `agent-provision-on-issue-comment.yml` | Issue comment | Provision new runner agent | SSH to runners |
| `runner-self-heal.yml` | Schedule | Auto-fix unhealthy runners | Ansible, SSH |
| `legacy-node-cleanup.yml` | Dispatch | Clean up legacy runner nodes | SSH |

**Use Case:** Self-hosted runner orchestration and healing

---

### 5. **Deployment & Release** (22 workflows)
Canary deployments, progressive rollouts, release management

**Key Workflows:**
| Workflow | Trigger | Purpose | Rollout Strategy |
|----------|---------|---------|------------------|
| `canary-deployment.yml` | Manual | Progressive canary to 10% → 50% → 100% | Blue-green |
| `progressive-rollout.yml` | Dispatch | Batched progressive deployment | Custom batches |
| `slsa-provenance-release.yml` | Release | Create SLSA provenance for releases | Code signing |

**Use Case:** Safe, progressive deployments to production

---

### 6. **Monitoring & Observability** (19 workflows)
Metrics, logs, health checks, alerting

**Key Workflows:**
| Workflow | Trigger | Purpose | Observability |
|----------|---------|---------|---------------|
| `observability-monitor.yml` | Schedule | Collect metrics + health status | Prometheus/Grafana |
| `issue-tracker-automation.yml` | Schedule | Auto-track provisioning status | GitHub Issues |
| `remediation-dispatcher.yml` | Workflow Dispatch | Dispatch remediation based on errors | Error routing |

**Use Case:** Operational visibility and alerting

---

### 7. **Notification & Communication** (14 workflows)
Slack, email, issue comments, status updates

**Key Workflows:**
| Workflow | Trigger | Purpose | Channels |
|----------|---------|---------|----------|
| `store-slack-to-gsm.yml` | Workflow Dispatch | Store Slack webhooks in GSM | GSM, Slack |
| `issue-comment-automation.yml` | Issue comment | Respond to issue comments | GitHub Issues |

**Use Case:** Keep teams informed of automation state

---

### 8. **GCP & Permission Management** (16 workflows)
GCP setup, permission validation, workload identity

**Key Workflows:**
| Workflow | Trigger | Purpose | Purpose |
|----------|---------|---------|---------|
| `gcp-permission-validator.yml` | Dispatch | Validate GCP IAM setup | Permission audit |

**Use Case:** Cloud platform validation and setup

---

### 9. **Security & Compliance** (15 workflows)
Secret rotation, security scanning, compliance checks

**Key Workflows:**
| Workflow | Trigger | Purpose | Security Function |
|----------|---------|---------|-------------------|
| `secret-rotation-coordinator.yml` | Schedule | Coordinate credential rotations | Vault rotation |
| `cosign-sign-artifacts.yml` | Release | Sign artifacts with Cosign | Code signing |

**Use Case:** Security posture and compliance validation

---

### 10. **Issue & PR Management** (14 workflows)
Auto-label, auto-close, auto-comment, workflow dispatch from issues

**Key Workflows:**
| Workflow | Trigger | Purpose | Function |
|----------|---------|---------|----------|
| `auto-label-on-cloud-provision.yml` | Issue | Label issues based on event | Issue triage |
| `advanced-issue-response.yml` | Issue opened | Smart issue response | Automation status |

**Use Case:** Intelligent issue/PR automation

---

### 11. **Administrative & Control** (15 workflows)
Admin tasks, approvals, orchestration, system commands

**Key Workflows:**
| Workflow | Trigger | Purpose | Admin Function |
|----------|---------|---------|-----------------|
| `issue-tracker-automation.yml` | Schedule | Track provisioning tasks | Ops visibility |
| `dismiss-stale-reviews.yml` | Schedule | Auto-dismiss old PR reviews | PR hygiene |

**Use Case:** System orchestration and governance

---

## Workflows by Trigger Type

### **Schedule Triggers** (37 workflows)
Run on fixed schedule (cron)
```
automation-health-validator.yml     - Every 6h
runner-self-heal.yml               - Every 30m
terraform-phase2-drift-detection.yml - Daily
issue-tracker-automation.yml        - Every 2h
...
```

### **Dispatch Triggers** (52 workflows)
Run manually via `workflow_dispatch`
```
cloud-ops-bootstrap.yml            - Deploy all cloud resources
terraform-auto-apply.yml          - Apply terraform changes
agent-provision-on-issue-comment.yml - Provision runner
...
```

### **Push Triggers** (41 workflows)
Run on git push (branch filters available)
```
e2e-validate.yml                   - Validate on every push
secrets-scan.yml                   - Scan on every push
validate-manifests.yml             - Validate manifests
...
```

### **Issue/PR Triggers** (31 workflows)
Run on issue/PR events
```
advanced-issue-response.yml        - On issue open
auto-label-on-cloud-provision.yml  - On issue label
auto-merge-dependabot.yml          - On dependabot PR
...
```

### **Workflow_Call Triggers** (22 workflows)
Reusable workflows called by other workflows
```
fetch-aws-creds-from-gsm.yml       - Called by: terraform-apply
portal-sync-validate.yml           - Called by: portal workflows
...
```

### **Release Triggers** (14 workflows)
Run on GitHub release creation
```
slsa-provenance-release.yml        - Create SLSA provenance
mirror-release-artifacts.yml       - Mirror release artifacts
...
```

---

## Most Complex Workflows

**High-dependency, multi-stage workflows that coordinate others:**

| Workflow | Stages | Calls Other Workflows | Dependencies | Error Impact |
|----------|--------|----------------------|--------------|--------------|
| `automationhealth-validator.yml` | 5 | 3 other workflows | AWS, GCP, Vault | 🔴 Critical |
| `cloud-ops-bootstrap.yml` | 8 | 5 other workflows | AWS, GCP, Terraform, Vault | 🔴 Critical |
| `progressive-rollout.yml` | 10+ | 4 other workflows | Load balancer, DNS, Health checks | 🔴 Critical |
| `issue-tracker-automation.yml` | 6 | 2 other workflows | GitHub API, provisioning status | 🟠 High |
| `terraform-auto-apply.yml` | 4 | 2 other workflows | AWS OIDC, GSM | 🟠 High |

---

## Workflow Dependencies

### **Critical Path** (workflows that must succeed for system to run)

```
cloud-ops-bootstrap.yml
    ├─→ terraform-plan.yml
    ├─→ terraform-apply.yml
    ├─→ elasticache-apply-gsm.yml
    └─→ portal-sync-validate.yml

automation-health-validator.yml
    ├─→ terraform-phase2-drift-detection.yml
    ├─→ runner-self-heal.yml
    └─→ issue-tracker-automation.yml

progressive-rollout.yml
    ├─→ canary-deployment.yml
    ├─→ health-check.yml
    └─→ rollback-on-failure.yml
```

### **Conditional Dependencies** (workflows that call others based on conditions)

```
auto-trigger-on-label.yml
    └─→ terraform-auto-apply.yml [if labeled "terraform"]

issue-tracker-automation.yml
    ├─→ auto-resolve-missing-secrets.yml [if secrets missing]
    ├─→ agent-provision-on-issue-comment.yml [if provisioning needed]
    └─→ runner-self-heal.yml [if runner unhealthy]

advanced-issue-response.yml
    └─→ auto-run-on-ops.yml [if issue from ops]
```

---

## Quick Reference Commands

```bash
# List all workflows
ls -1 .github/workflows/ | sort

# Show workflow count by category
ls .github/workflows/*.yml | sed 's/.*\///;s/-[^-]*$//' | \
  sort | uniq -c | sort -rn

# Find dispatch workflows (manual trigger)
grep -l "workflow_dispatch" .github/workflows/*.yml | wc -l

# Find scheduled workflows
grep -l "schedule:" .github/workflows/*.yml | wc -l

# Find workflows using specific secret
grep -l "secrets\.AWS_OIDC_ROLE_ARN" .github/workflows/*.yml

# Show which workflows call other workflows (dependencies)
grep -l "uses:.*workflows/" .github/workflows/*.yml

# Show workflow triggers at a glance
for f in .github/workflows/*.yml; do
  echo "$(basename $f): $(grep -E '^on:|workflow_call|schedule:|workflow_dispatch' $f | head -1)"
done | head -20

# Export all workflows as list
echo "Workflow Name,Category,Trigger Type,Complexity" > workflows.csv
for f in .github/workflows/*.yml; do
  # Parse and add to CSV
done
```

---

## Finding the Right Workflow

### "I need to deploy to production"
→ Look at: **Deployment & Release** category
→ Recommended: `progressive-rollout.yml` or `canary-deployment.yml`
→ Check dependencies: `cloud-ops-bootstrap.yml` must succeed first

### "My runners are unhealthy"
→ Look at: **Runner Management** category
→ Recommended: `runner-self-heal.yml` (auto), `legacy-node-cleanup.yml` (manual)
→ Trigger: Schedule (every 30m) or manual

### "I need to provision cloud resources"
→ Look at: **Infrastructure & Cloud Provisioning** category
→ Recommended: `cloud-ops-bootstrap.yml` (one-click), `terraform-auto-apply.yml` (git-ops)
→ Check dependencies: Must have AWS OIDC or GSM secrets configured

### "I need to validate something"
→ Look at: **CI/CD & Testing** category
→ Recommended: `e2e-validate.yml` (comprehensive), `validate-manifests.yml` (k8s)
→ Trigger: Manual or automatic on push

### "I'm debugging a failure"
→ Look at: **Monitoring & Observability** category
→ Use: `issue-tracker-automation.yml` for status
→ Use: `remediation-dispatcher.yml` for error routing

---

## Common Workflow Patterns

### Pattern 1: Scheduled Health Check + Auto-Remediate
```
automation-health-validator.yml (schedule: every 6h)
    └─→ Detects issues
        └─→ Dispatches: runner-self-heal.yml
            └─→ Detects: pod unhealthy
                └─→ Dispatches: legacy-node-cleanup.yml
```

### Pattern 2: Git-Ops with Approval
```
push to terraform/** branch
    └─→ auto-trigger-on-label.yml (trigger on label)
        └─→ Calls: terraform-plan.yml
            └─→ Comment on PR with plan
                └─→ Manual approval
                    └─→ Calls: terraform-apply.yml
```

### Pattern 3: Progressive Deployment
```
Release created
    └─→ slsa-provenance-release.yml (sign)
        └─→ Manual: dispatch progressive-rollout.yml
            └─→ Stage 1: Deploy to 10%
            └─→ Health check
            └─→ Stage 2: Deploy to 50%
            └─→ Health check
            └─→ Stage 3: Deploy to 100%
```

---

## Troubleshooting: Which Workflow Should I Look At?

### Symptom: "Terraform changes aren't applying"
1. Check: `terraform-auto-apply.yml` — is it running?
2. Check: `auto-trigger-on-label.yml` — did it trigger?
3. Check: AWS OIDC secret — is `AWS_OIDC_ROLE_ARN` set?
4. Check: `issue-tracker-automation.yml` — what's the error?

### Symptom: "Runners are failing"
1. Check: `runner-self-heal.yml` — did it run?
2. Check: `automation-health-validator.yml` — what's unhealthy?
3. Check: `legacy-node-cleanup.yml` — cleanup needed?
4. Check logs: `/tmp/runner.log` on runner host

### Symptom: "Secrets are missing"
1. Check: `auto-resolve-missing-secrets.yml` — did it run?
2. Check: `gcp-permission-validator.yml` — what's missing?
3. Check: `issue-tracker-automation.yml` — status report?

---

## Related Documentation

- **[SECRETS_INDEX.md](SECRETS_INDEX.md)** — What secrets each workflow uses
- **[SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md)** — What scripts workflows call
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — How to add new workflows
- **[DEVELOPER_SECRETS_GUIDE.md](DEVELOPER_SECRETS_GUIDE.md)** — Secret best practices

---

## Quick Stats

| Metric | Count |
|--------|-------|
| **Total Workflows** | 197 |
| **Scheduled** | 37 |
| **Manual Dispatch** | 52 |
| **Push-triggered** | 41 |
| **Issue/PR-triggered** | 31 |
| **Workflow_Call (reusable)** | 22 |
| **Release-triggered** | 14 |

---

*Last Updated: March 7, 2026*  
*Maintained by: DevOps & Automation Team*  
*Next Review: June 7, 2026*
