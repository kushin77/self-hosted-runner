# elasticache-params-EXAMPLE.tfvars — Template with discovered values
# This is a reference file showing discovered AWS network resources.
# Copy this to elasticache-params.tfvars and adjust as needed.

aws_region = "us-east-1"

# OPTION 1: Use discovered DEFAULT VPC (simplest, less isolated)
# Copy one of these configurations to elasticache-params.tfvars
vpc_id = "vpc-0c24d33925800050b"

# Use any 2-3 of these subnets across different AZs (recommended: at least 2)
subnet_ids = [
  "subnet-0f519178a250407de",  # us-east-1a
  "subnet-025cf8c26797df449"   # us-east-1b
]

# OPTION 2: Use discovered CUSTOM VPC (recommended for isolation)
# Uncomment below if you have subnets in custom VPC vpc-03046114c6bd47ce9
# vpc_id = "vpc-03046114c6bd47ce9"
# subnet_ids = [
#   "subnet-YOUR_CUSTOM_SUBNET_1",
#   "subnet-YOUR_CUSTOM_SUBNET_2"
# ]

# Optional security settings
allowed_security_groups = [
  # "sg-0123456789abcdef0"  # Uncomment and add security group IDs if desired
]

allowed_cidr_blocks = [
  # "10.0.0.0/16"  # Uncomment and add CIDR blocks if desired
]

# Static auth token (optional, leave empty for auto-generated)
auth_token = ""

tags = {
  Project     = "elevatediq-runners"
  Environment = "prod"
  ManagedBy   = "Terraform"
  Owner       = "Platform Team"
}

# INSTRUCTIONS:
# 1. Copy this file to elasticache-params.tfvars
# 2. Uncomment and edit the option you prefer (Option 1 or 2)
# 3. Verify vpc_id and subnet_ids are correct
# 4. Merge into PR #1314 or create new PR
# 5. Set AWS_OIDC_ROLE GitHub repo secret
# 6. Trigger elasticache-apply-safe.yml with apply=true
