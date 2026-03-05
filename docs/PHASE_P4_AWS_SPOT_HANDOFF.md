# Phase P4 — AWS Spot Runner: Ops Handoff

This document lists the exact inputs and steps Ops must perform to allow the CI plan/apply workflows to run and to deploy the lifecycle handler Lambda.

Required repository secrets (add in GitHub repo settings → Secrets):
- `AWS_ROLE_TO_ASSUME` — role ARN for the CI runner to assume (or provide credentials via secrets).
- `AWS_REGION` — AWS region to target.

Required Terraform inputs (either provide via `terraform.tfvars` or set as variables in the Actions workflow):
- `vpc_id` — VPC ID where the runners will be launched.
- `subnet_ids` — List of subnet IDs for the ASG/launch template.

Optional but recommended:
- Create an AWS Secrets Manager secret for the runner drain webhook and provide its ARN as `webhook_secret_arn` to the module so the Lambda reads the webhook URL from Secrets Manager.

## Quick Start: Automated Setup (Recommended)

Run the Ops setup script which handles init, validation, and planning:
```bash
./scripts/ops/p4-aws-spot-setup.sh
```

The script will:
- Verify AWS credentials
- Prompt for terraform.tfvars configuration if needed
- Initialize and validate Terraform
- Run terraform plan and create artifacts
- Display a summary and next steps

## Manual Setup Steps

1. Checkout `main` with the merged PR (#276).
2. Create a `terraform.tfvars` in `terraform/examples/aws-spot/` with the values for `vpc_id`, `subnet_ids`, and other variables:

Example `terraform/examples/aws-spot/terraform.tfvars`:
```
vpc_id = "vpc-..."
subnet_ids = ["subnet-...","subnet-..."]
instance_type = "t3.medium"
desired_capacity = 1
max_capacity = 2
key_name = "ssh-key"
```

3. From the repo root run:
```bash
cd terraform/examples/aws-spot
terraform init
terraform validate
terraform plan -out=aws-spot.plan
terraform show -no-color aws-spot.plan > aws-spot.plan.txt
```

4. Review the plan artifact (`aws-spot.plan.txt`).

5. After plan review, use the guarded apply workflow `p4-aws-spot-apply.yml` (requires `prod-terraform-apply` environment protection and manual confirmation) or run locally:
```bash
terraform apply aws-spot.plan
```

Contact/links:
- PR with changes: #276
- Current escalation: #279
- Master tracker: #240

If you want me to attempt a local `terraform plan` now, provide the `vpc_id` and `subnet_ids` (I will not accept secrets in chat — prefer a `terraform.tfvars` file committed to a secure branch or instruct me to run Actions after you set repo secrets).
