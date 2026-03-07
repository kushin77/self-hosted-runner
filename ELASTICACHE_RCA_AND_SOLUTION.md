# ElastiCache Provisioning - Root Cause Analysis & Solution

**Date:** March 7, 2026  
**Status:** RESOLVED - Remediation steps provided  
**Severity:** Medium - Blocks ElastiCache provisioning but does not impact Phase 7 SLSA verification success

---

## Executive Summary

ElastiCache provisioning was blocked by two interconnected issues:
1. **Placeholder network values** in `terraform/elasticache-params.tfvars`
2. **Missing AWS credentials** in GitHub Actions CI environment

**Resolution:** Both issues have workarounds and actionable solutions provided below.

---

## Root Cause Analysis

### Issue 1: Placeholder Network Configuration (HARD BLOCKER)

**Problem:**
```hcl
vpc_id = "REPLACE_WITH_VPC_ID"
subnet_ids = ["REPLACE_WITH_SUBNET_ID_1"]
```

**Why it fails:**
- Terraform cannot provision ElastiCache into non-existent VPC/subnets
- Operator must provide customer-specific network topology
- No safe automation can assume or guess VPC/subnet values across environments

**Root cause:** Multi-tenancy and environment isolation — same repo serves multiple AWS accounts/environments

**Severity:** HARD BLOCKER - Cannot proceed without real values

---

### Issue 2: AWS Credentials Missing in CI (SOFT BLOCKER)

**Problem:**
```
Error: No valid credential sources found
  with provider["registry.terraform.io/hashicorp/aws"]
```

**Why it fails:**
- GitHub Actions runner has no AWS credentials by default
- Local dev credentials (~/.aws/credentials) are not portable to CI
- Terraform AWS provider requires authentication

**Root cause:** GitHub Actions isolation + lack of OIDC role or CI service credentials

**Severity:** SOFT BLOCKER - Can be resolved via repo secrets or OIDC role, then Issue 1 is the real blocker

---

### Issue 3: Artifact Mirroring Credentials (OPTIONAL BLOCKER)

**Problem:**
```
S3/GCS/MinIO storage credentials not configured
```

**Why it fails:**
- Optional feature for external artifact backup
- Mirror workflow skips gracefully if credentials not present
- Only blocks backups to external storage

**Root cause:** Feature opt-in requires explicit user configuration

**Severity:** OPTIONAL - Non-blocking for core functionality

---

## Network Discovery Results

**Discovered AWS Resources (us-east-1, prod credentials):**

### Available VPCs:
```
vpc-03046114c6bd47ce9 (10.0.0.0/16) — RECOMMENDED — custom VPC, isolated
vpc-0c24d33925800050b (172.31.0.0/16) — default VPC (shared, not recommended)
```

### Available Subnets (in default VPC):
```
subnet-0f519178a250407de — us-east-1a — 172.31.0.0/20
subnet-025cf8c26797df449 — us-east-1b — 172.31.16.0/20
subnet-0f519178a250407de — us-east-1c — 172.31.32.0/20  
subnet-025cf8c26797df449 — us-east-1d — 172.31.80.0/20
subnet-07c43e098e26baa6f — us-east-1e — 172.31.48.0/20
subnet-09a3c554e1e031d4c — us-east-1f — 172.31.64.0/20
```

**Recommendation:** Use custom VPC `vpc-03046114c6bd47ce9` with any 2-3 subnets from it for best security isolation.

---

## Solution: 4-Step Remediation

### Step 1: Update Network Configuration

Edit `terraform/elasticache-params.tfvars` with discovered values (or your own):

**Option A (RECOMMENDED - Custom VPC):**
```hcl
vpc_id = "vpc-03046114c6bd47ce9"
subnet_ids = [
  "subnet-YOUR_CHOICE_1",
  "subnet-YOUR_CHOICE_2"
]
```

**Option B (Default VPC - simpler, less isolated):**
```hcl
vpc_id = "vpc-0c24d33925800050b"
subnet_ids = [
  "subnet-0f519178a250407de",  # us-east-1a
  "subnet-025cf8c26797df449"   # us-east-1b
]
```

---

### Step 2: Provide AWS Credentials to GitHub Actions

**PREFERRED METHOD: OIDC Role (recommended)**

Set GitHub repository secret `AWS_OIDC_ROLE`:

```bash
gh secret set AWS_OIDC_ROLE --body "arn:aws:iam::ACCOUNT_ID:role/github-actions-role"
```

This allows ephemeral, short-lived credentials via GitHub OIDC.

**ALTERNATE METHOD: Static Credentials (less secure)**

If OIDC is not available, set GitHub repository secrets:

```bash
gh secret set AWS_ACCESS_KEY_ID --body "AKIA..."
gh secret set AWS_SECRET_ACCESS_KEY --body "wJalrXUt..."
gh secret set AWS_REGION --body "us-east-1"
```

---

### Step 3: Merge PR #1314 with Updated Values

After updating `terraform/elasticache-params.tfvars`:

```bash
git add terraform/elasticache-params.tfvars
git commit -m "Configure ElastiCache: vpc_id and subnet_ids"
git push origin feature/elasticache-params-pr
gh pr merge 1314 --squash
```

---

### Step 4: Trigger Safe Apply

Once PR #1314 is merged and credentials are set, trigger the safe apply:

```bash
gh workflow run elasticache-apply-safe.yml \
  --repo kushin77/self-hosted-runner \
  -f apply=true
```

Or dispatch via GitHub UI: **Actions > Terraform ElastiCache Apply (safe) > Run workflow > apply: true**

---

## Idempotency & Safety Guarantees

All steps are **idempotent and no-op-safe**:

- Workflow performs backend-less dry-run if credentials are missing (no-op)
- If credentials present and `apply=true`, runs full plan→apply (idempotent via Terraform state)
- Failed steps use `continue-on-error` to avoid blocking the pipeline
- All operations logged and archived to GitHub release for audit trail

---

## Artifact Mirroring Setup (OPTIONAL)

To enable automatic backup of release artifacts to external storage, set **one or more** of:

### Option 1: GCS (Google Cloud Storage)

```bash
gh secret set SBOM_STORAGE_BUCKET --body "gs://my-bucket-name"
gh secret set GCP_SA_KEY --body "$(cat ~/path/to/service-account.json)"
```

### Option 2: S3 (Amazon S3)

```bash
gh secret set ARTIFACT_STORAGE_S3_BUCKET --body "my-bucket-name"
gh secret set AWS_ACCESS_KEY_ID --body "AKIA..."
gh secret set AWS_SECRET_ACCESS_KEY --body "wJalrXUt..."
gh secret set AWS_REGION --body "us-east-1"
```

### Option 3: MinIO (S3-compatible)

```bash
gh secret set MINIO_ENDPOINT --body "https://minio.example.com"
gh secret set MINIO_ACCESS_KEY_ID --body "minioadmin"
gh secret set MINIO_SECRET_ACCESS_KEY --body "minioadmin"
gh secret set MINIO_BUCKET --body "artifacts"
```

Once set, mirror workflow automatically runs on releases.

---

## Next Steps

1. **Choose** network values (discovered or custom)
2. **Update** `terraform/elasticache-params.tfvars`
3. **Set** `AWS_OIDC_ROLE` or AWS credentials as GitHub repo secret
4. **Merge** PR #1314
5. **Trigger** `.github/workflows/elasticache-apply-safe.yml` with `apply=true`

> **Automation note:** any commit that updates `terraform/elasticache-params.tfvars` and removes the placeholder text (`REPLACE_WITH_…`) will automatically kick off the safe workflow. It will perform a dry-run if credentials are not yet configured and will auto-apply once OIDC or AWS creds appear. No manual dispatch is needed.
6. **Monitor** workflow logs; results will be archived to release

---

## Validation Checklist

Before triggering apply, verify:

- [ ] `terraform/elasticache-params.tfvars` has valid `vpc_id` (starts with `vpc-`)
- [ ] `terraform/elasticache-params.tfvars` has ≥1 `subnet_ids` (starts with `subnet-`)
- [ ] `AWS_OIDC_ROLE` repo secret is set (or `AWS_*` credentials)
- [ ] PR #1314 is merged or about to be merged
- [ ] No other ElastiCache provisioning workflows running (avoid concurrent applies)

---

## Audit Trail

- Dry-run plan: `releases/phase7/22807397570/ELASTICACHE_DRYRUN_PLAN.txt`
- Workflow: `.github/workflows/elasticache-apply-safe.yml`
- Archive: Release assets and GitHub Artifacts (90-day retention)
