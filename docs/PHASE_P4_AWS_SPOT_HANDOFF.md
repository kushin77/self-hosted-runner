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

Local test / run steps (Ops can run these locally or via GitHub Actions):
1. Checkout `main` with the merged PR (#276).
2. Create a `terraform.tfvars` in `terraform/examples/aws-spot/` with the values for `vpc_id`, `subnet_ids`, and other variables (example below).

Example `terraform/examples/aws-spot/terraform.tfvars`:
```
vpc_id = "vpc-..."
subnet_ids = ["subnet-...","subnet-..."]
instance_type = "t3.medium"
desired_capacity = 1
max_capacity = 2
key_name = "ssh-key"
```

3. From the repo root run (if Terraform is installed):
```
cd terraform/examples/aws-spot
terraform init
terraform validate
terraform plan -out=aws-spot.plan
terraform show -json aws-spot.plan > aws-spot.plan.json
```

4. Upload `aws-spot.plan` as an artifact for review, or let the GitHub Actions `p4-aws-spot-deploy-plan.yml` run once the repo secrets and tfvars are in place.

5. After plan review, use the guarded apply workflow `p4-aws-spot-apply.yml` (requires `prod-terraform-apply` environment protection and manual confirmation).

Contact/links:
- PR with changes: #276
- Current escalation: #279
- Master tracker: #240

If you want me to attempt a local `terraform plan` now, provide the `vpc_id` and `subnet_ids` (I will not accept secrets in chat — prefer a `terraform.tfvars` file committed to a secure branch or instruct me to run Actions after you set repo secrets).
