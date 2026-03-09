# Phase 5: Workflow Migration Implementation Guide

**Status**: Ready for phase 5a-5d batch migration  
**Date**: 2026-03-09  
**Related Issues**: #1985, #1980 (INFRA-2000)

---

## Overview

Phase 5 migrates all 78+ GitHub workflows from direct secret access to ephemeral credential retrieval via OIDC + the credential action.

**Success Criteria**:
- ✅ All workflows use `get-ephemeral-credential@v1` action
- ✅ Zero `secrets.*` references in workflow env
- ✅ All workflows have `permissions.id-token: write`
- ✅ All credential steps include `audit-log: true`
- ✅ 100% workflow execution success rate

---

## Migration Batches

### Phase 5a: Test Workflows (5-10 workflows, 1 hour)

**Risk Level**: 🟢 LOW

**Examples**:
- `.github/workflows/lint.yml`
- `.github/workflows/unit-tests.yml`
- `.github/workflows/validate.yml`
- `.github/workflows/security-scan.yml`

**Approach**: Validate pattern, test thoroughly

**Migration Steps**:
1. Open one test workflow
2. Update workflow following template (see below)
3. Test: Manual dispatch or wait for next trigger
4. Validate: Success + audit logs show credential access
5. Repeat for 5-10 workflows in this category

**Expected Outcome**: Pattern validated, ready for scale

---

### Phase 5b: Build Workflows (15-20 workflows, 1.5 hours)

**Risk Level**: 🟡 MODERATE

**Examples**:
- `.github/workflows/build-*.yml`
- `.github/workflows/compile-services.yml`
- `.github/workflows/docker-build.yml`
- `.github/workflows/package-release.yml`

**Approach**: Batch update with testing

**Migration Pattern**:
1. Group 5 similar workflows
2. Apply template migration
3. Commit batch
4. Test: Allow scheduled triggers
5. Monitor success (target: 100%)
6. If successes, continue; if failures, debug and retry

**Expected Outcome**: All builds successful with ephemeral credentials

---

### Phase 5c: Deploy Workflows (20-25 workflows, 2 hours)

**Risk Level**: 🟠 HIGHER

**Examples**:
- `.github/workflows/deploy-staging.yml`
- `.github/workflows/deploy-production.yml`
- `.github/workflows/release-artifacts.yml`
- `.github/workflows/push-images.yml`

**Special Considerations**:
- Usually have multiple deployment secrets
- May require environment-specific credentials
- Higher blast radius if issues occur

**Migration Pattern**:
1. Small batches (3-5 workflows)
2. Extra validation before deployment
3. Staged approach: staging first, then production
4. Credential requirements documented per workflow

**Credential Mapping Example**:
```
deploy-production.yml:
  - AWS_ACCESS_KEY_ID → AWS_PRODUCTION_KEY
  - ROLE_ARN → AWS_PRODUCTION_ROLE
  - REGISTRY_TOKEN → DOCKER_PROD_TOKEN
```

**Expected Outcome**: All deployments successful, no credential errors

---

### Phase 5d: Infrastructure Workflows (15-20 workflows, 2 hours)

**Risk Level**: 🔴 HIGHEST

**Examples**:
- `.github/workflows/terraform-plan.yml`
- `.github/workflows/terraform-apply.yml`
- `.github/workflows/sops-decrypt.yml`
- `.github/workflows/vault-rotation.yml`

**Special Considerations**:
- Manage production infrastructure
- May have interdependencies
- Rollback procedures essential
- Extensive testing required

**Backup & Test Strategy**:
1. Double-check backups exist (migrate-workflows script)
2. Test in dry-run mode first
3. Small team review before infrastructure changes
4. Have rollback plan ready

**Expected Outcome**: Infrastructure operations rock-solid, zero manual secret management

---

## Migration Template

### Before Migration (Example)

```yaml
name: Deploy API

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Deploy to AWS
        run: ./scripts/deploy.sh
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          DATABASE_PASSWORD: ${{ secrets.DATABASE_PASSWORD }}
```

### After Migration (Using Template)

```yaml
name: Deploy API

permissions:
  id-token: write      # Required for OIDC token exchange

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      # NEW: Get ephemeral credentials for each secret
      - name: Get AWS Credentials
        id: aws_creds
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: AWS_ACCESS_KEY_ID
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true
      
      - name: Get AWS Secret
        id: aws_secret
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: AWS_SECRET_ACCESS_KEY
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true
      
      - name: Get Database Password
        id: db_pass
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: DATABASE_PASSWORD
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true
      
      # UPDATED: Use credentials from action outputs
      - name: Deploy to AWS
        run: ./scripts/deploy.sh
        env:
          AWS_ACCESS_KEY_ID: ${{ steps.aws_creds.outputs.credential }}
          AWS_SECRET_ACCESS_KEY: ${{ steps.aws_secret.outputs.credential }}
          DATABASE_PASSWORD: ${{ steps.db_pass.outputs.credential }}
```

---

## Key Changes Summary

### 1. Add Permissions
```yaml
permissions:
  id-token: write       # Enables OIDC token generation
```

### 2. Add Step ID for Reuse
```yaml
- name: Get Credential [NAME]
  id: cred_lowercase_name   # Must be lowercase, used for output reference
  uses: kushin77/get-ephemeral-credential@v1
```

### 3. Update Environment Variables
```yaml
# Before:
  env:
    SECRET: ${{ secrets.SECRET_NAME }}

# After:
  env:
    SECRET: ${{ steps.step_id.outputs.credential }}
```

### 4. Handle Multiple Credentials

For workflows with many credentials:

```yaml
steps:
  # Get all credentials in single step with caching
  - name: Get All Credentials
    id: credentials
    uses: kushin77/get-ephemeral-credential@v1
    with:
      credential-name: ALL_PRODUCTION_SECRETS
      retrieve-from: 'auto'
      cache-ttl: 1200
      audit-log: true
  
  # OR: Get each credential with cache reuse
  - name: Get Service Credentials
    id: svc_creds
    uses: kushin77/get-ephemeral-credential@v1
    with:
      credential-name: SERVICE_API_KEY
      cache-ttl: 1200
```

---

## Step-by-Step Migration Process

### Step 1: Prepare (5 minutes)

```bash
# Run validation
bash scripts/validate-credential-system.sh

# Analyze workflows
bash scripts/test-workflow-integration.sh

# Create migration backups
bash scripts/migrate-workflows-phase5.sh
```

### Step 2: Select Batch (5 minutes)

```bash
# Phase 5a: Test workflows (start here)
cd .github/workflows
ls *test*.yml *lint*.yml *validate*.yml | head -5
```

### Step 3: Update Single Workflow (10 minutes)

```text
1. Open workflow in editor
2. Add "permissions: {id-token: write}" after "name:"
3. For each "secrets.XXX" reference:
   a. Add credential step with id
   b. Replace "secrets.XXX" with "steps.id.outputs.credential"
4. Save and validate YAML
5. Commit workflow
```

### Step 4: Test Migration (15 minutes)

```bash
# Option A: Manual dispatch (if workflow has on.workflow_dispatch)
# - Go to GitHub UI
# - Click "Run workflow"
# - Wait for completion

# Option B: Wait for scheduled trigger
# - Next time workflow trigger fires

# Option C: Push commit and watch
# - If workflow triggers on push, it runs automatically
```

### Step 5: Validate Results (10 minutes)

```bash
# Check workflow run succeeded
# - Open GitHub Actions tab
# - Review workflow logs
# - Verify credential steps executed
# - Check audit logs in results

# Expected in logs:
# ✅ "Got credential successfully via layer: GSM|Vault|KMS"
# ✅ "Cache hit: false" (first run)
# ✅ "Audit logged: ..."
```

### Step 6: Commit and Repeat

```bash
git commit -m "Phase 5: Migrate workflow-name to ephemeral credentials

- Added permissions.id-token: write
- Added get-ephemeral-credential actions for:
  * CREDENTIAL_1
  * CREDENTIAL_2
- Updated environment variables to use credential outputs
- Validated workflow YAML

Related: #1985"

# Proceed to next workflow in batch
```

---

## Troubleshooting Migration Issues

### Issue: "permission denied: id-token"

**Cause**: Missing or incomplete OIDC setup

**Solution**:
```yaml
permissions:
  id-token: write       # Must be present in workflow
```

### Issue: "Credential not found"

**Cause**: Credential name mismatch or not in GSM/Vault/KMS yet

**Solution**:
1. Verify credential in GSM:
   ```bash
   gcloud secrets list | grep CREDENTIAL_NAME
   ```
2. If missing, populate via credential-manager.sh
3. Ensure credential is labeled correctly

### Issue: "Cache miss - auth failed"

**Cause**: OIDC token generation failed

**Solution**:
1. Check GitHub Actions runner logs
2. Verify OIDC provider configured in GCP/AWS
3. Confirm service account has required permissions

### Issue: "Workflow times out"

**Cause**: Credential retrieval slower than expected

**Solution**:
1. Increase job timeout (default 360 mins usually OK)
2. Verify network connectivity to GSM/Vault/AWS
3. Check credential layer health:
   ```bash
   # Each day, health-check workflow validates all layers
   # Check GitHub Actions logs for health status
   ```

### Issue: "Workflow fails but was working with secrets"

**Cause**: Possible issues:
1. Step ID collision (duplicate IDs)
2. YAML syntax error
3. Credential not retrieved correctly

**Solution**:
1. Run YAML validator: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/file.yml'))"`
2. Check step IDs are unique and lowercase
3. Review credential manager logs on-demand:
   ```bash
   bash scripts/credential-manager.sh CREDENTIAL_NAME auto
   ```

---

## Performance Expectations

### Credential Retrieval Time

| Layer | Typical | Best Case | Worst Case |
|-------|---------|-----------|------------|
| Cache Hit | 50ms | 10ms | 100ms |
| GSM (fresh) | 500ms | 200ms | 2s |
| Vault (fresh) | 400ms | 150ms | 1.5s |
| KMS (fresh) | 600ms | 300ms | 2.5s |

**Optimization Strategies**:
1. Set `cache-ttl: 600` for credentials used in multiple steps
2. Batch-retrieve multiple credentials (use action labels)
3. Parallelize credential retrieval across workflow steps:
   ```yaml
   - id: cred1
     uses: get-ephemeral-credential@v1
     with: {credential-name: CRED1, cache-ttl: 600}
   
   - id: cred2
     uses: get-ephemeral-credential@v1
     with: {credential-name: CRED2, cache-ttl: 600}
   # Both run in parallel automatically
   ```

### Overall Workflow Impact

- **Phase 5a** (test): Negligible impact
- **Phase 5b** (build): +1-2 seconds per workflow
- **Phase 5c** (deploy): +2-3 seconds total (cached after first step)
- **Phase 5d** (infra): +3-5 seconds (multiple credentials)

---

## Batch Schedule Recommendation

### Week 1: Foundation
- **Mon**: Phase 5a (test workflows) - validate pattern
- **Tue-Wed**: Phase 5b Batch 1 (5-10 builds) - scale testing
- **Thu-Fri**: Phase 5b Batch 2 (5-10 builds) - proceed if successful

### Week 2: Production-Ready
- **Mon-Tue**: Phase 5c Batch 1 (5 deploys) - staging-focused
- **Wed-Thu**: Phase 5c Batch 2 (5-10 deploys) - production ramp-up
- **Fri**: Phase 5d Batch 1 (5 infra) - infrastructure validation

### Week 3: Completion
- **Mon-Tue**: Phase 5d Batch 2 (10-15 infra) - complete infrastructure
- **Wed-Thu**: Remaining workflows - any special cases
- **Fri**: Phase 6 validation - ensure all systems operational

---

## Rollback Procedure (If Needed)

If significant issues occur during migration:

```bash
# 1. Stop new migrations
# 2. Restore from backups
cd /home/akushnir/self-hosted-runner
BACKUP_DIR="workflow-migration-backups-YYYYMMDD_HHMMSS"

# Restore specific workflow
cp $BACKUP_DIR/workflow-name.yml.backup .github/workflows/workflow-name.yml

# OR: Restore all workflows
cp $BACKUP_DIR/* .github/workflows/

# 3. Commit rollback
git add .github/workflows/
git commit -m "Rollback to direct secrets (temporary) - investigating issue #XXXX"

# 4. Debug and analyze issue
# 5. Re-start migration after fix
```

---

## Success Metrics

Track these metrics throughout migration:

| Metric | Target | Phase 5a | Phase 5b | Phase 5c | Phase 5d |
|--------|--------|----------|----------|----------|----------|
| Workflow Success Rate | 100% | 100% | 100% | 100% | 100% |
| Avg Retrieval Time | <1s | <500ms | <1s | <1.5s | <2s |
| Audit Logs | 100% | 100% | 100% | 100% | 100% |
| No Long-Lived Secrets | YES | YES | YES | YES | YES |
| Cache Hit Rate | >50% | —— | >60% | >70% | >75% |

---

## Related Resources

- **Scripts**:
  - `scripts/credential-manager.sh` - Manual credential retrieval
  - `scripts/validate-credential-system.sh` - Test credentials in GSM
  - `scripts/test-workflow-integration.sh` - Validate workflow structure
  - `scripts/migrate-workflows-phase5.sh` - Analyze and batch workflows

- **Documentation**:
  - `EPHEMERAL_CREDENTIAL_SYSTEM_INFRA-2000.md` - Complete system guide
  - `GIT_GOVERNANCE_STANDARDS.md` - Governance framework

- **GitHub Issues**:
  - #1985 - Phase 5b: Workflow Updates
  - #1980 - INFRA-2000 Epic (coordination)

---

## Next Steps

1. ✅ Review Phase 5a test workflow list
2. ✅ Prepare first batch backups via migration script
3. ✅ Update first 5-10 test workflows manually
4. ✅ Test and validate all succeed
5. ✅ Proceed to Phase 5b if successful
6. ✅ Continue through phases until complete
7. → Phase 6: Production validation and go-live

---

**Document Version**: 1.0  
**Last Updated**: 2026-03-09  
**Status**: Ready for Phase 5 execution
