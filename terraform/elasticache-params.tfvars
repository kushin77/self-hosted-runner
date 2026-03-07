# elasticache-params.tfvars — branch PR placeholder for operator to fill
# This file is a candidate tfvars to be merged via PR to trigger an idempotent apply.

aws_region = "us-east-1"

# REQUIRED: set your VPC ID (example: "vpc-0123456789abcdef0")
vpc_id = "REPLACE_WITH_VPC_ID"

# REQUIRED: set your private subnet IDs (at least 1, recommended 2-3+ across AZs)
subnet_ids = [
  "REPLACE_WITH_SUBNET_ID_1",
  # "REPLACE_WITH_SUBNET_ID_2",
  # "REPLACE_WITH_SUBNET_ID_3",
]

# Optional security settings — prefer allowed_security_groups over CIDR
allowed_security_groups = [
  # "sg-0123456789abcdef0"
]

allowed_cidr_blocks = [
  # "10.0.0.0/16"
]

# If you want to provide a static auth token, set it here (32-128 alphanumeric)
auth_token = ""

tags = {
  Project     = "elevatediq-runners"
  Environment = "prod"
  ManagedBy   = "Terraform"
  Owner       = "Platform Team"
}

# IMPORTANT:
# - Do not merge until `vpc_id` and `subnet_ids` are updated with real values.
# - After merge I will run `terraform init && terraform plan -out=tfplan && terraform apply tfplan` and post outputs (sensitive values redacted).
