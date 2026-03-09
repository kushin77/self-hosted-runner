# Advanced Compliance Checks (24+)

This document describes the 24 advanced compliance checks implemented in `.github/scripts/advanced-compliance-checks.py`. These checks enforce enterprise-grade standards across all GitHub Actions workflows.

## Overview

The advanced compliance checker scans all workflows in `.github/workflows/` and validates 24 checks across 4 categories:

- **Credential Security** (6 checks): Multi-layer credential management, TTL, rotation, secret detection
- **Workflow Structure** (6 checks): Approval gates, idempotency, concurrency, timeouts, conditions
- **Audit & Compliance** (6 checks): Audit logging, rollback, disaster recovery, access control, encryption
- **Operational Excellence** (6 checks): Resource limits, ephemeral cleanup, monitoring, runbooks, SLA

**Total Coverage:** 24 checks × 114 workflows = 2,736 potential validation points

---

## Credential Security (6 checks)

### CRED_001: Multi-Layer Credential Fallback

**Purpose:** Ensure credentials follow defense-in-depth pattern with fallback layers (GSM → VAULT → KMS).

**Why It Matters:** Prevents single points of failure in credential management; ensures availability even if primary provider is down.

**Pass Criteria:**
- Workflow contains at least one step with credential fallback logic
- Pattern: `GSM` or `GOOGLE_SECRET_MANAGER` referenced in steps
- OR: `VAULT` or `HASHICORP_VAULT` referenced
- OR: `KMS` or `AWS_KMS` referenced

**Fail Example:**
```yaml
steps:
  - name: Deploy
    env:
      SECRET: ${{ secrets.HARDCODED_SECRET }}
    run: ./deploy.sh  # ❌ Single layer, no fallback
```

**Pass Example:**
```yaml
steps:
  - name: Get Credentials (GSM Primary)
    id: creds
    run: |
      gcloud secrets versions access latest --secret="prod-token" || \
      vault kv get -field=token secret/app || \
      aws secretsmanager get-secret-value --secret-id app-token
```

**Remediation:** Implement credential retrieval with fallback (GSM → VAULT → KMS).

---

### CRED_002: Credential TTL (< 24 hours)

**Purpose:** Enforce short-lived credentials to limit exposure window.

**Why It Matters:** Reduces impact if credentials are compromised; complies with SOC2/ISO27k standards.

**Pass Criteria:**
- Workflow contains credential/token generation with TTL < 24h
- Keywords: `ttl`, `TTL`, `expires`, `EXPIRES`, `duration`
- Value must be < 24h (< 86400 seconds)

**Fail Example:**
```yaml
- name: Generate Token
  run: |
    TOKEN=$(aws sts assume-role --duration-seconds 129600)  # ❌ 36 hours
    echo "TOKEN=$TOKEN" >> $GITHUB_ENV
```

**Pass Example:**
```yaml
- name: Generate Short-Lived Token
  run: |
    TOKEN=$(aws sts assume-role --duration-seconds 3600)  # ✓ 1 hour
    echo "TOKEN=$TOKEN" >> $GITHUB_ENV
```

**Remediation:** Reduce credential TTL to < 24 hours (recommend 1-4 hours).

---

### CRED_003: Auto-Rotation Strategy Documented

**Purpose:** Ensure workflows document credential rotation procedures.

**Why It Matters:** Automated rotation prevents manual oversight; ensures compliance with key rotation requirements.

**Pass Criteria:**
- Workflow contains documentation/comments about credential rotation
- Keywords: `rotation`, `rotate`, `refresh`, `renew`
- OR: Workflow triggers on schedule (credential refresh pattern)

**Fail Example:**
```yaml
steps:
  - name: Deploy with API Key
    env:
      API_KEY: ${{ secrets.API_KEY }}
    run: ./deploy.sh
    # ❌ No rotation strategy documented
```

**Pass Example:**
```yaml
# Credential rotation strategy:
# - Automated daily refresh via GitHub Actions secret rotation
# - Scheduled job updates secrets in GitHub every 24h
# - Fallback to VAULT if GitHub secret update fails
steps:
  - name: Refresh API Key
    if: github.event_name == 'schedule'  # Daily
    run: |
      NEW_KEY=$(curl -X POST https://api.example.com/rotate)
      # Update via GitHub CLI or API
```

**Remediation:** Add comments documenting rotation strategy, implement scheduled credential refresh job.

---

### CRED_004: No Hardcoded Secrets Detected

**Purpose:** Prevent accidental exposure of secrets in repository.

**Why It Matters:** Hardcoded secrets are the #1 source of credential compromise in CI/CD.

**Pass Criteria:**
- No secret values detected in workflow YAML
- No patterns matching: passwords, api_keys, tokens with hardcoded values
- Uses GitHub secrets (`${{ secrets.* }}`) or external providers only

**Fail Example:**
```yaml
env:
  DATABASE_PASSWORD: "super-secret-password-123"  # ❌ Hardcoded!
  API_TOKEN: "sk_prod_abc123xyz789"               # ❌ Hardcoded!
```

**Pass Example:**
```yaml
env:
  DATABASE_PASSWORD: ${{ secrets.DB_PASSWORD }}  # ✓ From secrets
install-deps:
  run: echo "Using API token from secure provider"
```

**Remediation:** Move all secrets to GitHub Secrets, vault, or secure provider; remove hardcoded values.

---

### CRED_005: Credential Layer Failover Tested

**Purpose:** Ensure failover between credential providers is actually tested.

**Why It Matters:** Failover must work in production; testing proves robustness.

**Pass Criteria:**
- Workflow contains test step for credential failover
- Keywords: `test`, `verify`, `validate`, `failover`
- AND: Multiple credential providers referenced (indicating failover setup)

**Fail Example:**
```yaml
steps:
  - name: Get Creds
    run: |
      gcloud secrets ... || vault kv get ...
      # ❌ No explicit test that failover works
```

**Pass Example:**
```yaml
# CREDENTIAL FAILOVER TEST
steps:
  - name: Test GSM Failover
    run: |
      # Test primary fails gracefully
      gcloud secrets ... 2>&1 | grep -q "access denied" && echo "Primary down, testing failover"
      
      # Test fallback works
      vault kv get secret/app && echo "✓ Failover successful"
```

**Remediation:** Add explicit test step validating failover logic works (e.g., simulate GSM outage, verify VAULT takes over).

---

### CRED_006: STS Token Validation (Temporary Credentials Only)

**Purpose:** Ensure AWS STS tokens are used instead of long-lived IAM keys.

**Why It Matters:** STS tokens are temporary (1-36h); permanent keys create persistent risks.

**Pass Criteria:**
- Workflow uses AWS STS (Security Token Service) for credentials
- Keywords: `sts`, `STS`, `assume-role`, `ASSUME_ROLE`, `session`
- OR: No long-lived AWS Key IDs (`AKIA*`) detected

**Fail Example:**
```yaml
env:
  AWS_ACCESS_KEY_ID: AKIAIOSFODNN7EXAMPLE      # ❌ Permanent key
  AWS_SECRET_ACCESS_KEY: wJalrXUtnFEMI/K7... # ❌ Permanent secret
```

**Pass Example:**
```yaml
- name: Assume Role (STS)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-actions
    aws-region: us-east-1
    # ✓ STS provides temporary credentials
```

**Remediation:** Use AWS STS `assume-role` instead of permanent IAM keys; configure OIDC provider in GitHub Actions.

---

## Workflow Structure (6 checks)

### STRUCT_007: Approval Gates on Deploy

**Purpose:** Require human approval before production deployments.

**Why It Matters:** Prevents accidental deployments; adds human review gate for critical changes.

**Pass Criteria:**
- Deploy/production jobs contain environment-based approval
- Pattern: `environment:` with `deployment_branch_policy` or `required_reviewers`
- OR: Manual `workflow_dispatch` trigger with step approval

**Fail Example:**
```yaml
deploy-prod:
  runs-on: ubuntu-latest
  steps:
    - name: Deploy to Production
      run: ./deploy.sh  # ❌ No approval gate
```

**Pass Example:**
```yaml
deploy-prod:
  runs-on: ubuntu-latest
  environment: production  # ✓ Requires environment approval
  steps:
    - name: Deploy to Production
      run: ./deploy.sh
```

**Remediation:** Add `environment:` section to deploy job, configure required reviewers in GitHub repo settings.

---

### STRUCT_008: Idempotent Guards on Mutating Jobs

**Purpose:** Ensure mutating jobs (deploy, delete, update) are idempotent and safe to retry.

**Why It Matters:** Network failures may cause re-runs; idempotency prevents double-deploys or data corruption.

**Pass Criteria:**
- Mutating jobs contain idempotency check/guard
- Keywords: `idempotent`, `--no-delete`, `--dry-run`, `diff`, `state`, `check`
- Pattern: Job validates current state before making changes

**Fail Example:**
```yaml
deploy:
  steps:
    - name: Scale Service
      run: |
        kubectl scale deployment/app --replicas=3  # ❌ Not idempotent
        # If run twice, still scales to 3, but no verification
```

**Pass Example:**
```yaml
deploy:
  steps:
    - name: Scale Service (Idempotent)
      run: |
        CURRENT=$(kubectl get deployment app -o jsonpath='{.spec.replicas}')
        if [ "$CURRENT" != "3" ]; then
          kubectl scale deployment/app --replicas=3
        fi
        # ✓ Idempotent: only acts if current state != desired
```

**Remediation:** Add idempotency checks (get current state, verify desired state before applying change).

---

### STRUCT_009: Concurrency Group Configured

**Purpose:** Ensure concurrent job execution is controlled via concurrency groups.

**Why It Matters:** Prevents race conditions; ensures only one deploy runs at a time.

**Pass Criteria:**
- Workflow contains `concurrency:` block at job level or top level
- Format: `concurrency: { group: '...', cancel-in-progress: ... }`

**Fail Example:**
```yaml
deploy:
  runs-on: ubuntu-latest
  steps:
    - run: ./deploy.sh  # ❌ No concurrency control
    # If triggered twice, both run simultaneously → race condition
```

**Pass Example:**
```yaml
deploy:
  runs-on: ubuntu-latest
  concurrency:
    group: production-deploy
    cancel-in-progress: false  # ✓ Only one at a time
  steps:
    - run: ./deploy.sh
```

**Remediation:** Add `concurrency:` block with group name matching workflow/environment.

---

### STRUCT_010: Job Timeout Configured

**Purpose:** Prevent runaway jobs from consuming runner resources indefinitely.

**Why It Matters:** Network failures, deadlocks, or infinite loops should be auto-killed.

**Pass Criteria:**
- Job contains `timeout-minutes:` setting (recommended: 5-60 min depending on job)
- Value > 0 and reasonable (not 999999)

**Fail Example:**
```yaml
deploy:
  runs-on: ubuntu-latest
  steps:
    - run: ./deploy.sh  # ❌ No timeout, may run forever
```

**Pass Example:**
```yaml
deploy:
  runs-on: ubuntu-latest
  timeout-minutes: 30  # ✓ Kill job if > 30 minutes
  steps:
    - run: ./deploy.sh
```

**Remediation:** Add `timeout-minutes:` to job definition (recommend 30 min for deploys, 5 min for tests).

---

### STRUCT_011: Run Conditions Documented

**Purpose:** Ensure conditional execution is documented and intentional.

**Why It Matters:** Conditions control when jobs run; undocumented conditions cause confusion.

**Pass Criteria:**
- Workflow contains comments explaining conditional logic
- Keywords: `if:`, comment explaining condition
- OR: Readable `if:` condition that's self-documenting

**Fail Example:**
```yaml
deploy:
  if: github.ref == 'refs/heads/main'  # ❌ No comment explaining why
  steps:
    - run: ./deploy.sh
```

**Pass Example:**
```yaml
deploy:
  # Only deploy on main branch pushes (not PRs)
  if: github.ref == 'refs/heads/main' && github.event_name == 'push'
  steps:
    - run: ./deploy.sh
```

**Remediation:** Add comments explaining conditional logic for future maintainers.

---

### STRUCT_012: Idempotency Markers Present

**Purpose:** Flag steps as idempotent or require specific safeguards.

**Why It Matters:** Helps developers understand safe re-run behavior and failure recovery.

**Pass Criteria:**
- Jobs contain comments/markers indicating idempotency status
- Keywords: `idempotent`, `retryable`, `safe-to-rerun`
- OR: Step uses `continue-on-error: true` with recovery strategy

**Fail Example:**
```yaml
steps:
  - name: Create Database
    run: psql -c "CREATE DATABASE mydb;"  # ❌ Not idempotent, fails on retry
```

**Pass Example:**
```yaml
steps:
  - name: Create Database (Idempotent)
    # Safe to retry: CREATE IF NOT EXISTS pattern
    run: psql -c "CREATE DATABASE IF NOT EXISTS mydb;"
    # ✓ Marked idempotent via comment
```

**Remediation:** Add idempotency comments or markers; refactor non-idempotent steps to be safe for retry.

---

## Audit & Compliance (6 checks)

### AUDIT_013: State Changes Logged to Audit Trail

**Purpose:** Record all state modifications for compliance audit.

**Why It Matters:** Regulatory requirements (SOC2, FedRAMP, ISO27k) require auditable logs of state changes.

**Pass Criteria:**
- Workflow contains audit logging step
- Keywords: `audit`, `log`, `compliance-audit-logger`, `AUDIT`
- Pattern: Calls audit script or logs to audit trail system

**Fail Example:**
```yaml
deploy-prod:
  steps:
    - run: kubectl apply -f deploy.yaml  # ❌ No audit log
```

**Pass Example:**
```yaml
deploy-prod:
  steps:
    - run: kubectl apply -f deploy.yaml
    - name: Log to Audit Trail
      if: success()
      run: |
        bash scripts/compliance-audit-logger.sh log \
          "kubernetes_deploy" \
          "success" \
          "24" "0"  # ✓ Audit logged
```

**Remediation:** Add step calling `compliance-audit-logger.sh` after state-changing operations.

---

### AUDIT_014: Rollback Strategy Documented

**Purpose:** Document how to undo changes if deployment fails.

**Why It Matters:** Prevents stuck deployments; enables quick recovery from bad changes.

**Pass Criteria:**
- Workflow contains rollback documentation/strategy
- Keywords: `rollback`, `revert`, `previous`, `backup`
- Pattern: Step or comment explains rollback procedure

**Fail Example:**
```yaml
deploy-prod:
  steps:
    - run: kubectl apply -f deploy.yaml  # ❌ No rollback plan
```

**Pass Example:**
```yaml
deploy-prod:
  steps:
    - name: Backup Current Deployment
      run: |
        kubectl get deployment app -o yaml > /tmp/backup.yaml
        # ✓ Backup saved for rollback
    
    - name: Deploy New Version
      run: kubectl apply -f deploy.yaml
    
    - name: Rollback if Health Check Fails
      if: failure()
      run: kubectl apply -f /tmp/backup.yaml
```

**Remediation:** Document rollback steps; implement automated rollback on deployment failure.

---

### AUDIT_015: Disaster Recovery Plan Tested

**Purpose:** Ensure recovery procedures actually work under failure conditions.

**Why It Matters:** Untested recovery plans fail when needed most; testing proves resilience.

**Pass Criteria:**
- Workflow contains disaster recovery test
- Keywords: `dr-test`, `recovery`, `failover`, `simulate`
- Pattern: Scheduled job or manual trigger to validate recovery

**Fail Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh  # ❌ No DR testing
```

**Pass Example:**
```yaml
dr-test:
  name: Disaster Recovery Test
  if: github.event_name == 'schedule'  # Weekly test
  steps:
    - name: Simulate Outage & Recovery
      run: |
        # Simulate primary failure
        kubectl delete pod -l app=myapp --grace-period=0
        
        # Verify failover works
        sleep 30
        kubectl get pods -l app=myapp | grep -q Running || exit 1
        echo "✓ DR test passed"
```

**Remediation:** Add scheduled job to test disaster recovery (weekly minimum).

---

### AUDIT_016: Access Control Enforced (Least Privilege)

**Purpose:** Ensure jobs use minimum required permissions (least privilege principle).

**Why It Matters:** Limits blast radius if workflow is compromised.

**Pass Criteria:**
- Workflow contains explicit `permissions:` block
- Permissions scoped to only required APIs
- Examples: `contents: read`, `id-token: write` (not `write` for all)

**Fail Example:**
```yaml
permissions:
  contents: write
  packages: write
  pull-requests: write
  # ❌ Too broad, all-write access
```

**Pass Example:**
```yaml
permissions:
  id-token: write      # Only needed for OIDC
  contents: write      # Only needed for version tag
  checks: write        # Only needed for status checks
  # ✓ Least privilege
```

**Remediation:** Audit job permissions, remove unnecessary scopes, use most restrictive setting possible.

---

### AUDIT_017: Encryption in Transit (HTTPS Only)

**Purpose:** Ensure all network communication is encrypted.

**Why It Matters:** Prevents man-in-the-middle attacks; required for SOC2 compliance.

**Pass Criteria:**
- HTTP requests use HTTPS (not HTTP)
- Keywords: `https://`, `--secure`, `TLS`, `ssl`
- No HTTP URLs in network calls

**Fail Example:**
```yaml
steps:
  - run: curl http://api.example.com/deploy  # ❌ Unencrypted HTTP
```

**Pass Example:**
```yaml
steps:
  - run: curl https://api.example.com/deploy  # ✓ HTTPS
```

**Remediation:** Replace `http://` with `https://`; add TLS verification flags.

---

### AUDIT_018: Encryption at Rest (KMS-Wrapped)

**Purpose:** Ensure sensitive data is encrypted at rest using KMS.

**Why It Matters:** Protects data if storage is compromised.

**Pass Criteria:**
- Workflow encrypts artifacts or secrets at rest
- Keywords: `KMS`, `encryption`, `crypt`, `encrypted`
- Pattern: Uses AWS KMS or similar for data encryption

**Fail Example:**
```yaml
steps:
  - name: Store Secret
    run: echo "${{ secrets.API_KEY }}" > secret.txt  # ❌ Plaintext on disk
```

**Pass Example:**
```yaml
steps:
  - name: Store Secret (Encrypted)
    run: |
      echo "${{ secrets.API_KEY }}" | \
      aws kms encrypt --key-id arn:aws:kms:region:account:key/id \
      --plaintext fileb:///dev/stdin --query CiphertextBlob \
      --output text > secret.txt.kms
      # ✓ KMS encrypted
```

**Remediation:** Use AWS KMS, Google Secret Manager, or similar to encrypt sensitive data at rest.

---

## Operational Excellence (6 checks)

### OPS_019: Resource Limits Set

**Purpose:** Avoid runaway resource consumption on runners.

**Why It Matters:** Prevents shared runner exhaustion; enables fair scheduling.

**Pass Criteria:**
- Workflow contains resource limits on jobs/containers
- Keywords: `cpu`, `memory`, `limit`, `max`, `timeout`
- Values are reasonable (not 999GB)

**Fail Example:**
```yaml
test:
  runs-on: ubuntu-latest
  steps:
    - run: npm test  # ❌ No resource limits
```

**Pass Example:**
```yaml
test:
  runs-on: ubuntu-latest
  strategy:
    matrix:
      # ✓ Parallel jobs limited to 4 concurrent
      max-parallel: 4
  steps:
    - run: npm test
```

**Remediation:** Add `strategy.max-parallel` or container resource limits.

---

### OPS_020: Ephemeral Cleanup Configured

**Purpose:** Clean up temporary resources created during workflow.

**Why It Matters:** Prevents resource leaks; saves costs; avoids naming conflicts.

**Pass Criteria:**
- Workflow contains cleanup step
- Keywords: `cleanup`, `delete`, `remove`, `rm -rf`, `finally`
- Pattern: `if: always()` step that removes temporary resources

**Fail Example:**
```yaml
deploy:
  steps:
    - run: mkdir /tmp/config && cp config.yaml /tmp/config/  # ❌ No cleanup
```

**Pass Example:**
```yaml
deploy:
  steps:
    - run: mkdir /tmp/config && cp config.yaml /tmp/config/
    
    - name: Cleanup Temp Files
      if: always()
      run: rm -rf /tmp/config  # ✓ Always cleanup
```

**Remediation:** Add explicit cleanup step with `if: always()` to ensure cleanup on success or failure.

---

### OPS_021: Monitoring/Alerting Configured

**Purpose:** Alert on workflow failures or anomalies.

**Why It Matters:** Ensures issues are detected and remediated quickly.

**Pass Criteria:**
- Workflow contains alerting/monitoring
- Keywords: `slack`, `pagerduty`, `alert`, `notify`, `webhook`
- Pattern: Notification step on failure

**Fail Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh
    # ❌ Failure not notified
```

**Pass Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh
    
    - name: Notify on Failure
      if: failure()
      uses: slackapi/slack-github-action@v1
      with:
        webhook-url: ${{ secrets.SLACK_WEBHOOK }}
        # ✓ Failure alert sent to Slack
```

**Remediation:** Add notification step (Slack, PagerDuty) on workflow failure.

---

### OPS_022: On-Call Runbook Linked

**Purpose:** Provide incident response procedure for failures.

**Why It Matters:** Enables fast resolution; prevents escalation delays.

**Pass Criteria:**
- Workflow contains link to runbook or incident procedure
- Keywords: `runbook`, `document`, `wiki`, `procedure`, `README`
- Pattern: URL comment linking to runbook

**Fail Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh  # ❌ No runbook link
```

**Pass Example:**
```yaml
deploy:
  # On-call runbook: https://wiki.example.com/runbooks/deploy-failure
  steps:
    - run: ./deploy.sh
```

**Remediation:** Add comment with runbook URL; link to incident response procedure.

---

### OPS_023: Post-Mortem Template Present

**Purpose:** Enable structured post-incident analysis.

**Why It Matters:** Prevents repeat incidents; enables continuous improvement.

**Pass Criteria:**
- Workflow contains post-mortem template or reference
- Keywords: `postmortem`, `post-mortem`, `incident`, `retrospective`
- Pattern: Link to post-mortem template or process

**Fail Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh  # ❌ No post-mortem process
```

**Pass Example:**
```yaml
deploy:
  # Post-mortem template: https://wiki.example.com/templates/postmortem
  # Process documentation: https://wiki.example.com/processes/incident-response
  steps:
    - run: ./deploy.sh
```

**Remediation:** Add post-mortem template reference; document incident review process.

---

### OPS_024: SLA/Objectives Documented

**Purpose:** Define reliability targets (uptime, RTO, RPO).

**Purpose:** Enable informed prioritization; tie incidents to business metrics.

**Pass Criteria:**
- Workflow or service contains documented SLA
- Keywords: `SLA`, `RTO`, `RPO`, `uptime`, `objective`, `target`
- Values documented (e.g., "99.9% uptime", "5-minute RTO")

**Fail Example:**
```yaml
deploy:
  steps:
    - run: ./deploy.sh  # ❌ No SLA documented
```

**Pass Example:**
```yaml
deploy:
  # SLA: 99.95% uptime, 5-min RTO, 15-min RPO
  # Target: Deployment success rate > 99%
  steps:
    - run: ./deploy.sh
```

**Remediation:** Document SLA targets in workflow comments or linked documentation.

---

## Testing & Validation

### Running the Scanner

```bash
# Run full compliance check on all workflows
python3 .github/scripts/advanced-compliance-checks.py

# Example output:
# 🔍 Scanning 114 workflows...
# ✓ test.yml                                  | 24 checks |  0 violations | 18 warnings
# ❌ deploy-production.yml                    | 24 checks |  1 violations | 14 warnings
#
# ================================================================================
# 📊 Advanced Compliance Summary
# ================================================================================
# Total Checks: 2736
# Passed: 2268 (82%)
# Violations: 8 (0.3%)
# Warnings: 460 (17%)
```

### Remediation Workflow

1. **Review Violations:** Identify workflows with violations
2. **Fix Issues:** Apply remediation guidance for each check
3. **Test Changes:** Run scanner again to verify fixes
4. **Document:** Add comments explaining compliance decisions
5. **Monitor:** Track progress toward 100% compliance

---

## Integration with CI/CD

The policy-enforcement-gate workflow (.github/workflows/policy-enforcement-gate.yml) runs these checks every 4 hours and on-demand:

```yaml
- name: Run Advanced Compliance Checks
  run: python3 .github/scripts/advanced-compliance-checks.py
```

Results are logged to the audit trail for compliance tracking.

---

## References

- **SOC2 Compliance:** https://www.aicpa.org/interestareas/informationsystems/assurance-advisory-services/aicpasoc2.html
- **ISO 27001:** https://www.iso.org/isoiec-27001-information-security-management.html
- **FedRAMP:** https://www.fedramp.gov/
- **GitHub Actions Security:** https://docs.github.com/en/actions/security-guides

---

## Questions?

See `.github/scripts/advanced-compliance-checks.py` for implementation details, or contact the security team.

