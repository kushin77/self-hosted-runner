# Workflow Standards & Best Practices

**Version:** 1.0 | **Last Updated:** 2026-03-08

This document outlines the mandatory standards for all GitHub Actions workflows in this repository. Compliance is enforced by the [`policy-enforcement-gate.yml`](.github/workflows/policy-enforcement-gate.yml) workflow.

---

## 1. Workflow Naming & Structure

### 1.1 File Naming
- Use lowercase `kebab-case` with `.yml` or `.yaml` extension
- Name should reflect purpose and environment, e.g.:
  - ✅ `terraform-apply-prod.yml`, `e2e-validate.yml`, `credential-rotation-enforce.yml`
  - ❌ `deploy.yml`, `DEPLOY.yml`, `Deploy`, `deployProd.yml`

### 1.2 Required Top-Level Fields
Every workflow **must** include:

```yaml
name: Human-Readable Workflow Name (v1.0)

on:
  # Explicitly list triggers; no defaults
  workflow_dispatch:
  schedule:
    - cron: '0 3 * * *'  # With timezone comment

permissions:
  contents: read
  actions: read
  # ... only what's needed
```

### 1.3 Metadata Comment Block
Add at the top (after `name:`):

```yaml
# ════════════════════════════════════════════════════════════════
# Purpose: Brief description of what this workflow does
# Owner: @username (Slack: @user | Email: user@example.com)
# SLA: Max 60min runtime; alert if >30min avg
# Runbook: docs/runbooks/workflow-name.md
# Dependencies: [workflow-a, workflow-b]  (if any)
# ════════════════════════════════════════════════════════════════
```

---

## 2. Permissions & Security

### 2.1 Explicit Permissions Block (Required)
Never omit `permissions:` or use defaults. Always specify all needed permissions:

```yaml
permissions:
  contents: read           # Read repo (default)
  actions: read            # List workflow runs
  id-token: write          # OIDC auth (if using Vault)
  issues: write            # Create/update issues
  pull-requests: write     # Comment on PRs
  # Do NOT use: write-all, secrets: inherit (unless critical)
```

### 2.2 Secret Handling (Mandatory OIDC)
- **Allowed:** `secrets.VAULT_ROLE_ID`, `${{ secrets.GITHUB_TOKEN }}`
- **Forbidden:** Hardcoded API keys, passwords, or tokens
- All credentials must source from Vault via OIDC or be ephemeral tokens

### 2.3 Secrets Inheritance Rule
If using `secrets: inherit` or `permissions: write-all`:
- Add a comment above explaining why (e.g., `# Must forward AWS creds to matrix jobs`)
- File an issue with label `security-review-needed`
- Get approval from security team before merge

---

## 3. Concurrency & Job Orchestration

### 3.1 Concurrency Guards (Deployment Jobs)
All workflows with `apply`, `deploy`, `rotate`, or `release` **must** declare concurrency:

```yaml
concurrency:
  group: terraform-apply-${{ matrix.env }}  # or just ${{ github.ref }}
  cancel-in-progress: false  # NEVER cancel deploys in-flight
```

### 3.2 Test & Validation Jobs
May use `cancel-in-progress: true` to save runner resources:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    concurrency:
      group: test-${{ github.ref }}
      cancel-in-progress: true  # OK for tests
```

### 3.3 Remediation Jobs
Use `cancel-in-progress: true` (latest fix wins):

```yaml
jobs:
  remediate:
    concurrency:
      group: remediation-${{ github.ref || github.run_id }}
      cancel-in-progress: true
```

---

## 4. Triggers: Allowed Patterns

### 4.1 Allowed Triggers

| Trigger | Frequency | Requirement | Example |
|---------|-----------|-------------|---------|
| `workflow_dispatch` | Any | No limit; document inputs | Run manually from UI |
| `schedule: cron` | ≤1 per 30min | Document business reason | `0 */2 * * *` (every 2h is OK) |
| `push: branches: [main]` | Per commit | Use with `paths:` filters | `paths: ['terraform/**']` |
| `pull_request` | Per PR event | Allowed; avoid sensitive ops | Test, lint, plan only |
| `workflow_run: workflows: [X]` | Auto-triggered | Specify condition (success/failure) | Only if upstream succeeds |
| `workflow_call` | For reuse | OK; expose `inputs:` and `outputs:` | Shared job library |

### 4.2 Forbidden/Restricted Triggers
- ❌ `push:` without `branches:` filter (too broad)
- ❌ `on: # everything` (implicit all events)
- ❌ `repository_dispatch` (requires allowlist; see [GOVERNANCE_ALLOWLIST.yaml](#))

### 4.3 Trigger Documentation
Add comment before `on:` with business case:

```yaml
# trigger: Runs daily at 3 AM UTC to rotate AWS credentials
# Justification: NIST 800-53 IA-4 (60-90 day key rotation)
on:
  schedule:
    - cron: '0 3 * * *'
```

---

## 5. Timeouts & Resource Limits

### 5.1 Job Timeout
All jobs must declare timeout:

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest
    timeout-minutes: 30  # Max 60 for production deploys
```

### 5.2 Step Timeout
Long-running steps should also have timeouts:

```yaml
- name: Run tests
  timeout-minutes: 15  # Override job timeout for specific step
  run: npm test
```

### 5.3 Resource Limits
- **Free runners:** Jobs ≤60min, no parallel >4 jobs
- **Self-hosted:** Jobs ≤120min, scale runners as needed

---

## 6. Audit & Logging

### 6.1 Mandatory Audit Logging for Deployments
Call audit script at workflow start & end:

```yaml
- name: Begin deployment audit
  run: |
    bash .github/scripts/audit-log.sh \
      --action deploy_start \
      --workflow "${{ github.workflow }}" \
      --run-id "${{ github.run_id }}" \
      --actor "${{ github.actor }}"

# ... deployment steps ...

- name: Complete deployment audit
  run: |
    bash .github/scripts/audit-log.sh \
      --action deploy_end \
      --status "${{ job.status }}" \
      --run-id "${{ github.run_id }}"
```

### 6.2 Structured Logging
Log operational events in JSON format for audit parsing:

```yaml
- name: Log event
  run: |
    echo '{
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "action": "terraform_apply",
      "resource": "prod/vpc",
      "status": "success",
      "changes": { "added": 3, "modified": 1, "destroyed": 0 }
    }' >> /tmp/audit.json
```

---

## 7. Error Handling & Notifications

### 7.1 Failure Notifications
Deploy jobs must notify on failure:

```yaml
- name: Notify on deployment failure
  if: failure()
  uses: 8398a7/action-slack@v3
  with:
    status: ${{ job.status }}
    text: 'Deployment failed: ${{ github.workflow }} #${{ github.run_number }}'
    webhook_url: ${{ secrets.SLACK_WEBHOOK }}
```

### 7.2 Graceful Degradation
Use `continue-on-error: true` only for non-critical steps:

```yaml
- name: Run optional check
  continue-on-error: true  # Will not fail workflow
  run: optional-check.sh
```

---

## 8. Reusable Workflows (`workflow_call`)

### 8.1 Reusable Job Pattern
Extract common logic into `.github/workflows/reusable-*.yml`:

```yaml
name: Reusable Terraform Validate

on:
  workflow_call:
    inputs:
      environment:
        type: string
        required: true
      terraform_root:
        type: string
        default: './terraform'
    outputs:
      validation_passed:
        value: ${{ jobs.validate.outputs.passed }}

jobs:
  validate:
    runs-on: ubuntu-latest
    outputs:
      passed: ${{ steps.validate.outputs.passed }}
    steps:
      # ... validation logic
```

### 8.2 Calling Reusable Workflows
```yaml
jobs:
  validate-terraform:
    uses: ./.github/workflows/reusable-terraform-validate.yml
    with:
      environment: staging
      terraform_root: ./infrastructure
```

---

## 9. Matrix Strategy & Parallelization

### 9.1 Matrix Variables
Use for testing across multiple environments/versions:

```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: [18, 19, 20]
        environment: [dev, staging]
    runs-on: ubuntu-latest
    steps:
      - run: npm test --version=${{ matrix.node-version }}
```

### 9.2 Concurrency with Matrix
Apply concurrency per matrix combination:

```yaml
concurrency:
  group: test-${{ github.ref }}-${{ matrix.node-version }}
  cancel-in-progress: true
```

---

## 10. Checklist for New Workflows

Before submitting a PR, ensure:

- [ ] Filename is lowercase kebab-case (e.g., `my-workflow.yml`)
- [ ] `name:` field is present and descriptive
- [ ] Metadata comment block added (purpose, owner, SLA, runbook)
- [ ] `permissions:` block is explicit and minimal
- [ ] No hardcoded secrets (use Vault or `secrets.*`)
- [ ] Triggers documented with business justification
- [ ] Deploy jobs have `concurrency:` guard
- [ ] Job/step timeouts set (≤60min default, ≤120min for prod)
- [ ] Audit logging added for sensitive operations
- [ ] Error handling & notifications in place
- [ ] CODEOWNERS review required (workflows/ path)
- [ ] Runs cleanly in dry-run without errors

---

## 11. Validation via `policy-enforcement-gate.yml`

All workflows are automatically validated by the `.github/workflows/policy-enforcement-gate.yml` workflow on PR. You'll receive feedback if standards aren't met. Common failures:

| Issue | Fix |
|-------|-----|
| Missing `name:` | Add descriptive `name: My Workflow Name` at top |
| No `permissions:` | Declare all needed permissions explicitly |
| Hardcoded secret detected | Use Vault OIDC or `${{ secrets.VAULT_* }}` |
| Deploy job lacks concurrency | Add `concurrency:` with `cancel-in-progress: false` |
| No trigger documentation | Add comment above `on:` block explaining why |

---

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Reusable Workflows Guide](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
- [Governance Framework](.github/governance/GOVERNANCE.md)
- [Policy Enforcement](.github/workflows/policy-enforcement-gate.yml)
