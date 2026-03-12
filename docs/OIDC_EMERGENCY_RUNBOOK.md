# AWS OIDC Federation - Emergency Runbook

> **Critical**: Use this runbook for OIDC authentication failures impacting production CI/CD

## Severity Levels

| Level | Description | Response Time |
|-------|-------------|----------------|
| P1 | All workflows failing, no AWS access | Immediate |
| P2 | Some workflows failing, partial access | 15 minutes |
| P3 | Degraded performance, intermittent failures | 1 hour |
| P4 | Configuration issues, no prod impact | 4 hours |

## Incident Response Flow

```
Incident Detected
    ↓
Page on-call engineer
    ↓
Assess severity (P1-P4)
    ↓
[P1/P2] Activate emergency response
[P3/P4] Standard troubleshooting
    ↓
Root cause analysis
    ↓
Fix implementation
    ↓
Verification & recovery
    ↓
Post-mortem & documentation
```

## P1: Total Authentication Failure

> **Symptoms**: All GitHub Actions workflows failing with OIDC errors

### Immediate Actions (0-5 minutes)

```bash
# 1. Check if OIDC provider still exists
aws iam list-open-id-connect-providers

# 2. Verify role exists and is accessible
aws iam get-role --role-name github-oidc-role

# 3. Check CloudTrail for errors
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 10

# 4. Review recent changes
git log --oneline -20 infra/terraform/modules/aws_oidc_federation/
```

### Rollback Strategy (5-10 minutes)

**Option A: Restore from Terraform State**
```bash
cd infra/terraform/modules/aws_oidc_federation

# Show current state
terraform state list

# If corrupted, refresh state
terraform refresh

# If state is bad, restore from backup
aws s3 cp s3://your-tf-state-bucket/backup/terraform.tfstate .

# Re-apply
terraform apply -auto-approve
```

**Option B: Recreate OIDC Provider**
```bash
# Delete broken provider
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

# Delete role
aws iam delete-role --role-name github-oidc-role

# Redeploy
./scripts/deploy-aws-oidc-federation.sh
```

### Verification (10-15 minutes)

```bash
# Run test suite
./scripts/test-aws-oidc-federation.sh

# Manually test
aws sts get-caller-identity

# Trigger test workflow
gh workflow run oidc-deployment.yml
gh run list -L 1 -w oidc-deployment.yml
gh run view <run-id> --log
```

### Communication (Parallel)

```bash
# Post update to GitHub issue
gh issue comment 2159 --body "🚨 P1 Incident: OIDC authentication failure. Investigating..."

# Slack (if configured)
curl -X POST https://hooks.slack.com/services/... \
  -H 'Content-Type: application/json' \
  -d '{"text": "🚨 AWS OIDC P1 Incident. All workflows failing."}'
```

## P2: Partial Authentication Failure

> **Symptoms**: Some workflows fail, intermittent OIDC errors

### Investigation (0-15 minutes)

```bash
# Check which workflows are failing
gh run list --status failed -L 20

# Check workflow logs
gh run view <run-id> --log

# Look for patterns in error messages
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  | jq '.Events[] | select(.CloudTrailEvent | fromjson | .errorCode)'

# Check IAM role policies
aws iam list-attached-role-policies --role-name github-oidc-role
aws iam list-role-policies --role-name github-oidc-role
```

### Common Fixes

**Fix 1: Missing Permissions**
```bash
# Add missing permission to role
aws iam put-role-policy \
  --role-name github-oidc-role \
  --policy-name missing-permission \
  --policy-document file://policy-addition.json

# Verify
aws iam get-role-policy --role-name github-oidc-role --policy-name missing-permission
```

**Fix 2: Trust Policy Issue**
```bash
# Backup current trust policy
aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument' > trust-policy-backup.json

# Update trust policy if needed
aws iam update-assume-role-policy \
  --role-name github-oidc-role \
  --policy-document file://corrected-trust-policy.json

# Verify
aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument' | jq .
```

**Fix 3: OIDC Provider Thumbprint**
```bash
# Get current GitHub OIDC thumbprints
curl -s https://token.actions.githubusercontent.com/.well-known/openid-configuration \
  | jq -r .jwks_uri

# Extract certificate
curl -s https://github.com/github-oidc-certificates/.well-known/openid-configuration

# If thumbprint changed, update provider
aws iam update-open-id-connect-provider-thumbprint \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Verification

```bash
# Test critical workflow
gh workflow run critical-deploy.yml --ref main

# Monitor
gh run list -L 1 -w critical-deploy.yml
gh run view <run-id> --shell --log | tail -50
```

## P3: Intermittent Failures

> **Symptoms**: Occasional timeout errors, sporadic 403s

### Check Resource Limits

```bash
# Check IAM API call rate limits
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 \
  | jq '.Events | length' # Should be < 50

# If high concurrency, check for throttling errors
aws cloudtrail lookup-events \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  | jq '.Events[] | select(.CloudTrailEvent | fromjson | .errorCode == "ThrottlingException")'
```

### Network Diagnostics

```bash
# Test connectivity to AWS STS
aws sts get-caller-identity --debug 2>&1 | grep -i "endpoint\|connection"

# Check GitHub Actions runner network
ping -c 3 8.8.8.8
dig +short token.actions.githubusercontent.com

# If GitHub Actions runner is self-hosted, check network config
ssh <runner-host> "bash -c 'ping -c 3 sts.amazonaws.com'"
```

### Rate Limit Mitigation

```bash
# If rate limited, add exponential backoff to workflows
cat > .github/workflows/deploy-with-backoff.yml << 'EOF'
    - name: Retry with exponential backoff
      run: |
        MAX_RETRIES=3
        RETRY_DELAY=5
        
        for i in $(seq 1 $MAX_RETRIES); do
          echo "Attempt $i..."
          aws sts get-caller-identity && break
          
          if [ $i -lt $MAX_RETRIES ]; then
            sleep $((RETRY_DELAY * i))
          else
            exit 1
          fi
        done
EOF
```

## P4: Configuration Issues

> **Symptoms**: New workflows not recognizing OIDC, documentation gaps

### Configuration Audit

```bash
# Check OIDC provider configuration
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

# Get role details
aws iam get-role --role-name github-oidc-role | jq .

# Verify trust policy
aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument' | jq .
```

### Documentation Updates

```bash
# Review and update OIDC documentation
nano docs/AWS_OIDC_FEDERATION.md

# Add troubleshooting examples
# Commit changes
git add docs/AWS_OIDC_FEDERATION.md
git commit -m "docs: Update OIDC troubleshooting guide"
git push origin main
```

## Diagnostic Commands

### Quick Health Check

```bash
#!/bin/bash
set -e

echo "🔍 AWS OIDC Health Check"
echo "========================================"

# 1. Provider exists
echo -n "✓ OIDC Provider... "
PROVIDER=$(aws iam list-open-id-connect-providers | grep -c token.actions.githubusercontent.com || true)
echo "$PROVIDER found"

# 2. Role exists
echo -n "✓ GitHub OIDC Role... "
ROLE=$(aws iam get-role --role-name github-oidc-role 2>/dev/null && echo "✅" || echo "❌")
echo "$ROLE"

# 3. Trust policy correct
echo -n "✓ Trust Policy... "
TRUST=$(aws iam get-role --role-name github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument' | grep -c 'federated' || true)
echo "$TRUST conditions found"

# 4. Policies attached
echo -n "✓ Policies Attached... "
POLICIES=$(aws iam list-attached-role-policies --role-name github-oidc-role \
  --query 'length(AttachedPolicies)' --output text)
echo "$POLICIES policies"

# 5. Recent CloudTrail events
echo -n "✓ CloudTrail Activity... "
EVENTS=$(aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 1 \
  --query 'length(Events)' --output text)
echo "$EVENTS recent events"

# 6. Workflow status
echo -n "✓ Recent Workflows... "
WORKFLOWS=$(gh run list -L 5 --json status | jq '[.[] | select(.status=="completed" and .conclusion=="success")] | length')
echo "$WORKFLOWS successful"

echo "========================================"
echo "Health check complete"
```

Save and run:
```bash
chmod +x diagnose-oidc.sh
./diagnose-oidc.sh
```

## Escalation Path

| Level | Contact | Channel | SLA |
|-------|---------|---------|-----|
| P1 | On-call Engineer | PagerDuty + Slack | 15 min |
| P2 | Team Lead | Slack + Email | 1 hour |
| P3 | Product Owner | Email + GitHub | 4 hours |
| P4 | Documentation | GitHub Issue | Next sprint |

## Recovery Procedures

### Option 1: Terraform State Restore

```bash
cd infra/terraform/modules/aws_oidc_federation

# List backups
aws s3 ls s3://your-state-bucket/backups/ | grep terraform.tfstate

# Restore from backup (choose timestamp)
aws s3 cp s3://your-state-bucket/backups/terraform.tfstate.2026-03-10-1400 ./

# Verify restore
terraform state list

# Re-apply with current code
terraform apply -auto-approve
```

### Option 2: Fresh Deployment

```bash
# Remove old OIDC resources (WARNING: will disconnect all workflows)
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com

aws iam delete-role-policy \
  --role-name github-oidc-role \
  --policy-name github-oidc-role-kms-operations

# ... delete all policies ...

aws iam delete-role --role-name github-oidc-role

# Redeploy
./scripts/deploy-aws-oidc-federation.sh

# Verify
./scripts/test-aws-oidc-federation.sh
```

### Option 3: Fallback to Long-Lived Keys (Emergency Only)

```bash
# Create temporary IAM user for emergency access
aws iam create-user --user-name github-actions-fallback

aws iam create-access-key --user-name github-actions-fallback

# Add to GitHub Secrets temporarily
gh secret set AWS_ACCESS_KEY_ID --body "<key-id>"
gh secret set AWS_SECRET_ACCESS_KEY --body "<secret-key>"

# Mark for remediation
echo "FALLBACK_ACTIVE=true" >> $GITHUB_ENV
echo "FALLBACK_EXPIRY=$(date -u -d '+7 days' +%Y-%m-%dT%H:%M:%SZ)" >> $GITHUB_ENV

# TODO: Remediate OIDC within 7 days
```

## Post-Incident

### Immediate Actions

1. **Document Root Cause**
   ```bash
   cat > post-mortems/oidc-incident-2026-03-11.md << 'EOF'
   # OIDC Incident Post-Mortem
   
   **Date**: 2026-03-11
   **Severity**: P2
   **Duration**: 45 minutes
   **Impact**: 8 workflows failed
   
   ## Root Cause
   [Description of root cause]
   
   ## Timeline
   - 14:00 UTC: First failure detected
   - 14:15 UTC: On-call engaged
   - 14:45 UTC: Fixed and verified
   
   ## Remediation
   - [Action 1]
   - [Action 2]
   
   ## Prevention
   - [Future action 1]
   - [Future action 2]
   EOF
   ```

2. **Update Runbook**
   ```bash
   # Add learnings to this runbook
   nano runbooks/oidc-emergency.md
   git add runbooks/oidc-emergency.md
   git commit -m "docs: Update OIDC runbook with incident learnings"
   git push origin main
   ```

3. **Alert on Patterns**
   ```bash
   # Check for recurring issues
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
     | jq '.Events[] | select(.CloudTrailEvent | fromjson | .errorCode)' | sort | uniq -c
   ```

### Long-Term Prevention

1. **Monitoring Setup**
   ```bash
   # Create CloudWatch alarm for OIDC failures
   aws cloudwatch put-metric-alarm \
     --alarm-name oidc-assume-role-failures \
     --alarm-actions arn:aws:sns:us-east-1:123456789012:alerts
   ```

2. **Automated Testing**
   ```bash
   # Add to CI/CD cron
   0 */4 * * * ./scripts/test-aws-oidc-federation.sh >> /var/log/oidc-tests.log
   ```

3. **Documentation Updates**
   - [ ] Updated troubleshooting guide
   - [ ] Added new common issue
   - [ ] Updated recovery procedures
   - [ ] Trained team on escalation

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-11  
**Next Review**: 2026-06-11  
**Owner**: Infrastructure Team
