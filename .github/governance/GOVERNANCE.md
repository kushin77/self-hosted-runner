# Global CI/CD Governance Framework
**Version:** 1.0 | **Date:** 2026-03-08 | **Status:** Active

---

## Executive Summary
This document establishes the global governance, guardrails, policies, and operational rules for all CI/CD automation, infrastructure deployments, and Secrets/Credentials management across the self-hosted runner infrastructure. It enforces **defense-in-depth**, **least-privilege**, **audit-first**, and **fail-secure** principles.

---

## 1. Core Governance Principles

### 1.1 Defense-in-Depth
- Multi-layer validation: policy → type-check → runtime → audit
- No single point of failure; cascading guardrails at every decision point
- Explicit approval gates for high-risk operations (Terraform apply, credential rotation, release)

### 1.2 Least-Privilege Access
- All workflows run with minimal required permissions
- Credentials are sourced from Vault (never stored in repo or GitHub Secrets)
- Service accounts and roles are scoped to specific jobs/environments

### 1.3 Audit-First
- Every deployment, change, and secret operation logged to a central audit store
- Audit logs are immutable and retained ≥90 days
- Real-time alerts for policy violations

### 1.4 Fail-Secure
- Default-deny: workflows must explicitly opt-in to risky operations
- Failed checks block progress (no warnings-only mode for P0 rules)
- Rollback triggers automatically if deployment health degrades

---

## 2. Workflow Governance Rules

### 2.1 Mandatory Standards for All Workflows
Every workflow file in `.github/workflows/` **must**:

| Rule | Requirement | Enforcement |
|------|-------------|-------------|
| **Naming** | `kebab-case.yml` with clear purpose (e.g., `terraform-apply-prod.yml`) | File name lint in `policy-enforcement-gate.yml` |
| **Description** | Include `name:` with human-readable description + version tag | Automated check on PR |
| **Concurrency** | Set `concurrency.group` and `cancel-in-progress` policy | Workflow must declare |
| **Permissions** | Explicit `permissions:` block; never use default | Required in schema validation |
| **Triggers** | Document trigger(s): `on:` only includes expected events | PR review enforces intent |
| **Timeouts** | Job timeout ≤ 60min, step timeout ≤ 15min (exception: data sync) | Enforced in template |
| **Secrets Handling** | Use Vault OIDC or `secrets.VAULT_*`; never hardcode | Pre-commit hook + scan |
| **Documentation** | Add comment block at top: purpose, owner, runbook link, SLA | Required in PR template |
| **Audit Logging** | Must call `.github/scripts/audit-log.sh` on start & end | Template enforcement |

**Failures:** Any workflow missing mandatory standards is **rejected at merge time**; no exceptions.

### 2.2 Trigger & Schedule Governance
| Trigger Type | Rule | Max Frequency | Auto-approval |
|--------------|------|---------------|---------------|
| `schedule` (cron) | ≤1 every 30 minutes; document business reason | 30m | None; manual gate for P0 |
| `workflow_dispatch` | Allowed; must have descriptive inputs | — | DevOps approval |
| `push` to `main` | Allowed only for low-risk jobs (tests, lints); must have branch protection | — | Auto if all checks pass |
| `workflow_run` | Allowed; must define exact upstream workflows and success/failure conditions | — | Auto if dependency succeeds |
| `repository_dispatch` | Blocked by default; only by explicit allowlist in `GOVERNANCE_ALLOWLIST.yaml` | — | Manual review required |

**Rule:** No workflow may trigger the same downstream job >2 parallel times. Concurrency group must deduplicate.

### 2.3 Job Concurrency & Serialization
- **Deploy jobs (apply, rotate, release):** `concurrency.group = <env>-deploy`, `cancel-in-progress: false` (prevents lost state)
- **Test/validation jobs:** `cancel-in-progress: true` (save resources)
- **Remediation jobs:** `concurrency.group = remediation`, `cancel-in-progress: true` (latest fix wins)

**Policy:** If a newer run arrives while an older is in progress on the same resource, the old run is cancelled **only if** it is not a deployment.

---

## 3. Terraform & Infrastructure Policy

### 3.1 Apply Gate Enforcement
**No Terraform apply may proceed without:**
1. ✅ Successful `terraform plan` output posted to PR (≥2 approvals if `destroy` detected)
2. ✅ SLSA provenance verified for plan artifact
3. ✅ Drift detection passed (no config skew vs. state)
4. ✅ Cost estimate reviewed (alert if >+10% from baseline)
5. ✅ Manual approval from designated ops-lead (via PR comment or workflow dispatch)
6. ✅ All branch protection rules passed (status checks, reviews, CODEOWNERS)

**Policy:** Auto-apply is **only** permitted for pre-approved, low-risk tiers (e.g., dev, sandbox); `prod` always requires manual gate.

### 3.2 State & Backend Security
- Terraform state stored in encrypted S3 + DynamoDB lock
- Backend credentials fetched from Vault OIDC; never committed to repo
- State is versioned; rollback available via `git revert` + plan
- Weekly state audit: drift detection, orphaned resources, cost anomalies

### 3.3 Module & Variable Policies
- All `.tf` files in `terraform/` must use modules from `terraform/modules/` (no inline resources >5 lines)
- Input variables locked to allowed types: `string`, `list(string)`, `map(string)`, `number` (no `any` type)
- Sensitive variables (e.g., passwords, API keys) marked as `sensitive = true`
- Variable defaults are validated (no empty strings for required vars; provide test fixtures)

---

## 4. Secrets & Credentials Governance

### 4.1 Credential Lifecycle
| Phase | Policy | Owner |
|-------|--------|-------|
| **Creation** | Use Terraform + Vault; never manual paste-in secrets | Infra Eng |
| **Rotation** | Automated every 90 days or on compromise; logged & audited | Auto-Rotate Workflow |
| **Leak Detection** | Gitleaks + Trivy scans on every PR; real-time scan in production | Security Workflow |
| **Revocation** | Immediate on expiry or incident; no grace period | Vault Admin |

### 4.2 GitHub Secrets Policy
- **Prohibited:** Storing credentials in GitHub Secrets (except temporary PAT for GitHub Actions itself)
- **Allowed:** Short-lived tokens (Vault auth, OIDC role ARNs, GitHub App IDs)
- All secrets must have a `GITHUB_SECRET_GOVERNANCE_TAG` label in `.env` (metadata file)

### 4.3 Vault Integration
- All credentials sourced from Vault via OIDC (no long-lived API keys)
- Vault audit log captures every credential request; retained indefinitely
- Policies enforce mTLS, IP whitelisting, and request signing

---

## 5. Approval & Change Control

### 5.1 Change Impact Levels
| Level | Definition | Approval Required | SLA |
|-------|-----------|-------------------|-----|
| **P0** | Prod deploy, credential rotation, state mutation, branch protection change | 2x independent ops-lead | <1h |
| **P1** | Non-prod deploy, terraform plan review, policy change | 1x ops-lead + automated checks | <4h |
| **P2** | Documentation, workflow refinement (non-functional), test additions | 1x engineering review | <24h |
| **P3** | Text/comment updates, CI metric improvements | Auto-merge if all checks pass | immediate |

### 5.2 Approval Workflow
1. PR author submits change with impact level label
2. `policy-enforcement-gate.yml` assigns reviewers based on label + file changes
3. Reviewers approve via PR comment (e.g., `/approve p0`) or GitHub review
4. Audit log records: who, when, context, and decision
5. Merge only after all requirements met + branch protection enforced

---

## 6. Logging, Audit & Compliance

### 6.1 Audit Log Schema
Every operation logged with:
```json
{
  "timestamp": "2026-03-08T14:32:01Z",
  "workflow": "terraform-apply-prod",
  "actor": "github-actions[bot]",
  "action": "deploy_start|deploy_end|policy_violation|approval",
  "resource": "prod/vpc",
  "status": "success|failure|rolled_back|cancelled",
  "changes": { "added": 3, "modified": 1, "destroyed": 0 },
  "approval": {"approver": "user@example.com", "timestamp": "2026-03-08T14:30:00Z"},
  "run_id": "22814196208",
  "severity": "info|warn|critical"
}
```

### 6.2 Audit Destinations
- **Primary:** CloudWatch Logs (`/aws/governance/audit`)
- **Secondary:** S3 export bucket (immutable, 365-day retention)
- **Real-time alerts:** SNS topic to security team on P0 violations

### 6.3 Compliance Reports
- **Daily:** Health check report (workflow success %, avg runtime, policy violations)
- **Weekly:** Risk assessment (outdated dependencies, overprivileged service accounts, unreviewed deploys)
- **Monthly:** Governance scorecard (policy adherence %, incident RCA, rollback frequency)

---

## 7. Guardrails: Automated Blocking Rules

### 7.1 Pre-Merge Guardrails
| Rule | Trigger | Action |
|------|---------|--------|
| **Secrets detected** | Gitleaks finds hardcoded API key/password | Reject PR, alert security team |
| **Overprivileged workflow** | Workflow requests `secrets: inherit` + `permissions: write-all` | Reject until narrowed |
| **Missing CODEOWNERS approval** | PR touches `.github/workflows/` without `.github/workflows/CODEOWNERS` signoff | Block merge |
| **Terraform destroy without approval** | Plan includes `destroy` but no `/approve p0` comment | Block apply gate |
| **Branch protection violation** | Force-push detected on `main` | Auto-revert via GitHub API |
| **Stale dependency** | Workflow action is >30 days old | Warn; ask to pin version |

### 7.2 Runtime Guardrails (Mid-Execution)
| Rule | Trigger | Action |
|------|---------|--------|
| **Credential leak in logs** | Step outputs contain `password=`, `secret=`, `token=` | Mask in logs; send alert |
| **Concurrent apply detected** | 2nd terraform apply triggered on same resource | Cancel 2nd run + notify operators |
| **Health check failure during deploy** | E2E smoke test fails mid-apply | Auto-rollback + incident ticket |
| **Cost spike** | Terraform plan delta >20% from baseline | Require explicit cost approval |
| **Orphaned resource** | Infra drift detected; resource in AWS but not in state | Alert + auto-import or destroy workflow |

### 7.3 Post-Merge Guardrails
| Rule | Trigger | Action |
|------|---------|--------|
| **Deployment failure in prod** | Workflow conclusion = `failure` on prod job | Incident ticket + page on-call |
| **Audit log anomaly** | >100 API calls in <1min from same workflow | Rate-limit + investigate |
| **Policy violation backfill** | Old workflow detected and doesn't meet current standards | Auto-file issue + label `governance-debt` |

---

## 8. Exceptions & Override Process

### 8.1 Policy Exception Request
**Only in genuine emergencies:**
1. File GitHub issue with label `policy-exception` + `SEV-0`
2. Provide: justification, risk assessment, mitigation, and expiry date
3. Requires 2x independent approvals (ops-lead + security-lead)
4. Auto-expires after 72 hours; must be re-approved for continuation
5. Logged & included in monthly audit report

### 8.2 Rollback Triggers (Auto-Exception Reversal)
- Any exception lapses if rollback is needed
- Failed health check during deployment reverts policy exception
- Manual `/revoke-exception <issue-id>` in GitHub comment reverses approval

---

## 9. Governance Enforcement Workflows

The following **mandatory** workflows implement governance:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `policy-enforcement-gate.yml` | `pull_request`, `workflow_dispatch` | Validates all governance rules before merge |
| `governance-audit-report.yml` | `schedule: 0 7 * * *` | Daily audit log analysis + compliance report |
| `credential-rotation-enforce.yml` | `schedule: 0 1 * * 0` (weekly) | Validates credentials not expired; rotates if needed |
| `terraform-approval-gate.yml` | `workflow_run: terraform-plan` | Blocks apply until manual approval + cost review |
| `reusable-guards.yml` | reusable workflow | Shared job library for all common guardrail checks |
| `branch-protection-enforcer.yml` | `schedule`, `workflow_dispatch` | Validates & auto-corrects branch protection rules |

---

## 10. Responsibilities & RACI Matrix

| Activity | DevOps | Security | Infra Eng | Eng Lead |
|----------|--------|----------|-----------|----------|
| Policy creation & updates | — | ✓ Lead | ✓ Input | ✓ Approval |
| Workflow reviews (pre-merge) | ✓ Primary | ✓ Secondary | — | ✓ If `.github/` touched |
| Approval gate (P0 deploys) | ✓ Primary | — | — | ✓ On-call |
| Incident response | ✓ Triage | ✓ Lead | ✓ Remediate | — |
| Audit log review | ✓ Daily | ✓ Weekly | — | — |
| Exception approval | ✓ Primary | ✓ Required | — | — |

---

## 11. Policy Versioning & Updates

- **Minor updates** (clarifications, rule refinements): Auto-merge to `main`, notify team via Slack
- **Major updates** (new guardrails, new approval tier): 7-day notice period, team discussion, explicit approval from Tech Lead
- **Emergency updates** (security incident): File `policy-incident-<date>.md`, immediate implementation, post-mortem within 24h

**Last Updated:** 2026-03-08  
**Next Review:** 2026-04-08  
**Owner:** DevOps / Security Lead  
**Approval:** Tech Lead, Security Lead
