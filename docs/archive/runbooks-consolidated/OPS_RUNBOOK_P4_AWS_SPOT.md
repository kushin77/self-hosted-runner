P4 AWS Spot Ops Runbook

Purpose
- Provide concise, copy-paste steps for Ops to add repository secrets, finalize `terraform.tfvars`, run the plan job, review artifacts, and execute guarded apply.

Required repository secrets (add as repository secrets):
- `AWS_ROLE_TO_ASSUME` : IAM Role ARN the CI should assume for Terraform operations.
- `AWS_REGION` : AWS region to target (e.g., `us-east-1`).

Recommended repository protection:
- Protect environment `prod-terraform-apply` and restrict to appropriate approvers prior to apply.

Immediate next steps for Ops
1. Add repository secrets (GitHub CLI example):

```bash
# Set repository secret values (replace placeholders)
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/CI-Terraform-Role"
gh secret set AWS_REGION --body "us-east-1"
```

(Alternatively, add via repo Settings → Secrets → Actions)

2. Replace example values in `terraform/examples/aws-spot/terraform.tfvars` with real VPC/subnet IDs and other environment-specific values, then merge PR #317.

3. After secrets exist and PR #317 is merged, the CI plan workflow will run automatically (`.github/workflows/p4-aws-spot-deploy-plan.yml`). To run manually:

```bash
# from repo root
gh workflow run p4-aws-spot-deploy-plan.yml --ref main
```

4. Review plan artifacts:
- The workflow uploads two artifacts: `plan.out` (binary) and `aws-spot.plan.txt` (human-readable summary). Download and review `aws-spot.plan.txt` for resources to be created/changed.

5. If plan is approved, trigger guarded apply via GitHub Actions (requires approver and environment protection):
- Approve the `prod-terraform-apply` environment and run the guarded apply workflow or use the Actions UI to trigger `p4-aws-spot-apply.yml`.

Local validation commands (Ops can run locally if preferred):

```bash
# ensure AWS credentials (assume role) are available in your environment
scripts/ops/p4-aws-spot-setup.sh
# or:
cd terraform/examples/aws-spot
terraform init
terraform validate
terraform plan -out=tfplan
terraform show -no-color tfplan > aws-spot.plan.txt
```

Post-apply verification
- Confirm created runners are healthy and registering with the control plane.
- Verify CloudWatch/Lambda lifecycle handler metrics and logs.
- Run post-deployment checks documented in `docs/PHASE_P4_DEPLOYMENT_READINESS.md` and issue #340.

Contacts and references
- PR to fill tfvars: #317
- Ops escalation issue: #325
- Portal live-channels Draft Issue: #337
- CI workflows: `.github/workflows/p4-aws-spot-deploy-plan.yml`, `.github/workflows/p4-aws-spot-apply.yml`
- Ops helper script: `scripts/ops/p4-aws-spot-setup.sh`

If you want, I can open a PR with this runbook and ping the Ops team in the PR/issue comments.