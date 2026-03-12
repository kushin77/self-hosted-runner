# AWS OIDC Migration Runbook — GitHub Workflows

**Date**: 2026-03-12  
**Authority**: Lead engineer approved  
**Scope**: Convert 5+ GitHub workflows from long-lived credentials to temporary OIDC tokens  
**Risk**: LOW (idempotent, rollback-safe, can migrate one workflow at a time)

---

## QUICK START

### Step 1: Update One Workflow File

Replace this block in `.github/workflows/your-workflow.yml`:

```yaml
# OLD — Long-lived credentials (DELETE AFTER TESTING)
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

With this block:

```yaml
# NEW — OIDC tokens (automatic renewal)
permissions:
  id-token: write  # Required for OIDC token generation

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Assume AWS role via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::830916170067:role/github-oidc-role
          aws-region: us-east-1
```

### Step 2: Test First Workflow

```bash
# Push the updated workflow to main or open a PR
git add .github/workflows/your-workflow.yml
git commit -m "feat: migrate workflow to AWS OIDC tokens"
git push origin [branch-or-main]

# Wait for workflow to run, check logs
# Expected: AWS CLI commands work without credential errors
# Check CloudTrail for OIDC token exchange logs

# If successful → move to next workflow
# If failed → revert and check AWS role permissions (next section)
```

### Step 3: Repeat for All Workflows

```bash
# List all workflows that use AWS credentials
grep -r "AWS_ACCESS_KEY_ID\|AWS_SECRET_ACCESS_KEY" .github/workflows/ | cut -d: -f1 | sort -u

# For each workflow:
#   1. Update permissions + action config (see template below)
#   2. Push to test branch
#   3. Wait for successful run
#   4. Merge to main
#   5. Delete old credentials from GitHub Secrets (once all workflows migrated)
```

---

## TEMPLATE FOR ALL WORKFLOW TYPES

### Standard Build/Test Workflow

```yaml
name: Build & Test with AWS

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # AWS OIDC token (automatic, expires 1 hour)
      - name: Assume AWS role
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::830916170067:role/github-oidc-role
          aws-region: us-east-1

      # Your existing build steps (unchanged)
      - name: Build
        run: |
          aws s3 ls s3://your-bucket/
          docker build -t myapp .
          # etc...
```

### Deployment Workflow (Requires Specific Permissions)

If your workflow needs specific AWS actions (e.g., S3 upload, CloudFormation, ECR push), the `github-oidc-role` must be granted those permissions. Current permissions:

```
✅ s3:* (full S3 access)
✅ kms:Decrypt, kms:DescribeKey, kms:GenerateDataKey
✅ sts:AssumeRole (for cross-account access)
✅ secretsmanager:GetSecretValue
```

If you need additional permissions, request them in issue #2636 or grant them via:

```bash
aws iam put-role-policy \
  --role-name github-oidc-role \
  --policy-name github-oidc-additional-permissions \
  --policy-document file://policy.json
```

### Parallel Workflow (Multiple Jobs)

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    # Permissions at job level (REQUIRED)
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::830916170067:role/github-oidc-role
          aws-region: us-east-1
      # ...

  deploy:
    runs-on: ubuntu-latest
    needs: build
    # IMPORTANT: Re-authenticate in dependent jobs
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::830916170067:role/github-oidc-role
          aws-region: us-east-1
      # ...
```

---

## MIGRATION CHECKLIST

### Pre-Flight

- [ ] Know your AWS account ID: `830916170067` ✓
- [ ] Know your OIDC role name: `github-oidc-role` ✓
- [ ] Confirm role trust policy includes your repo: `repo:kushin77/self-hosted-runner:*` ✓
- [ ] Get current IAM policies attached (listed above)

### Per-Workflow Migration

- [ ] Identify workflow that uses `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
- [ ] Add `permissions: { id-token: write }` to workflow
- [ ] Replace `configure-aws-credentials` action config (see template)
- [ ] Test on branch (do NOT push to main yet)
- [ ] Check GitHub Actions logs for successful AWS CLI executions
- [ ] Check AWS CloudTrail for OIDC token exchange logs
- [ ] Once successful, merge to main
- [ ] Repeat for next workflow

### Post-Flight (After All Workflows Migrated)

- [ ] All 5+ workflows running successfully with OIDC
- [ ] Zero errors related to AWS credentials
- [ ] CloudTrail shows OIDC token exchange logs (not password auth)
- [ ] Delete `AWS_ACCESS_KEY_ID` from GitHub Secrets
- [ ] Delete `AWS_SECRET_ACCESS_KEY` from GitHub Secrets
- [ ] Document completion in issue #2636
- [ ] Close issue #2636

---

## TROUBLESHOOTING

### Error: "Could not assume role"

**Cause**: Role trust policy doesn't include your repo/branch/environment

**Fix**:
```bash
# Check current trust policy
aws iam get-role \
  --role-name github-oidc-role \
  --query Role.AssumeRolePolicyDocument

# Should show:
# "Principal": { "Federated": "arn:aws:iam::830916170067:oidc-provider/..." }
# "Condition": { "StringEquals": { "...:sub": "repo:kushin77/self-hosted-runner:*" } }

# If missing, grant access (via #2636 issue or manually):
aws iam get-role-policy \
  --role-name github-oidc-role \
  --policy-name TrustPolicy
```

### Error: "Access Denied" for AWS operation

**Cause**: Role doesn't have permission for the AWS service you're calling

**Fix**:
```bash
# Check policies on role
aws iam list-role-policies --role-name github-oidc-role
aws iam get-role-policy \
  --role-name github-oidc-role \
  --policy-name [PolicyName]

# If permission missing, add via:
aws iam put-role-policy \
  --role-name github-oidc-role \
  --policy-name github-oidc-additional \
  --policy-document file://additional-permissions.json
```

### Error: "Token could not be obtained from OIDC provider"

**Cause**: GitHub Actions runner doesn't have internet access or OIDC provider is unavailable

**Fix**:
- Check GitHub Actions runner network (should be public or have egress to `token.actions.githubusercontent.com`)
- Confirm AWS account ID is correct in role ARN
- Wait a few minutes (GitHub OIDC provider caches trust policy)

### Workflow Works Locally but Not in GitHub Actions

**Cause**: Local env has `AWS_ACCESS_KEY_ID` set; GitHub Actions environment is clean

**Fix**:
- Remove local AWS credentials before running workflow
- Verify workflow doesn't accidentally pick up `~/.aws/credentials`
- Check GitHub Actions logs for environment variable leakage

---

## MONITORING & VERIFICATION

### Verify Token Exchange in CloudTrail

```bash
# Search CloudTrail for OIDC token exchanges (replace REPO with yours)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-items 20 \
  --region us-east-1
```

Expected output:
```
EventName: AssumeRoleWithWebIdentity
SourceIPAddress: 140.82.xxx.xxx (GitHub Actions IP)
PrincipalId: arn:aws:iam::830916170067:role/github-oidc-role/...
```

### Check Workflow Logs

```bash
# In GitHub Actions UI, look for:
[✓] Assume AWS role
[✓] aws sts get-caller-identity
# Output: Account: 830916170067, User: github-oidc-role
```

---

## ROLLBACK PLAN

If OIDC migration causes issues:

1. **Revert workflow file**:
   ```bash
   git revert [commit-hash]
   git push origin main
   ```

2. **Restore long-lived credentials** (if deleted):
   ```bash
   # Add back to GitHub Secrets:
   # AWS_ACCESS_KEY_ID = [from backup]
   # AWS_SECRET_ACCESS_KEY = [from backup]
   ```

3. **Re-run workflow**: Should work with old credentials

4. **Report issue**: Post to #2636 with logs and I'll help debug

---

## FREQUENTLY ASKED QUESTIONS

**Q: Do I need to update all workflows at once?**  
A: No. Migrate one at a time, test, then move to next. Safer and easier to debug.

**Q: Can I keep long-lived credentials while migrating?**  
A: Yes. Both can coexist during transition. Delete long-lived ones only after all workflows use OIDC.

**Q: What if a workflow is in a private repo (not kushin77/self-hosted-runner)?**  
A: Update the GitHub OIDC role trust policy to include other repos (request via #2636).

**Q: How long do OIDC tokens expire?**  
A: 1 hour (auto-refreshed by `aws-actions/configure-aws-credentials@v4`).

**Q: Can I use OIDC for other AWS accounts?**  
A: Yes. Use `role-to-assume` to assume a role in a different account (cross-account access).

**Q: Do I pay for OIDC tokens?**  
A: No. OIDC token exchanges are free; you only pay for AWS API calls.

---

## NEXT STEPS

1. **Select first workflow**: Pick one that uses `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`
2. **Apply template above**: Copy the OIDC config into your workflow
3. **Test on branch**: Push to a test branch, watch GitHub Actions logs
4. **Verify CloudTrail**: Check `AssumeRoleWithWebIdentity` logs
5. **Merge & repeat**: Once successful, move to next workflow
6. **Delete old credentials**: After all workflows migrated, delete GitHub Secrets
7. **Close issue #2636**: Comment with completion status

---

## REFERENCE

**Issue**: #2636 (AWS OIDC Federation Deployment)  
**Commit**: See git history for OIDC setup details  
**Documentation**: [AWS GitHub Actions OIDC Setup Guide](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

**Support**: Post in #2636 if issues arise during migration.

---

*Runbook generated: 2026-03-12T04:30:00Z*  
*Authority: Lead Engineer (Direct Deployment)*
