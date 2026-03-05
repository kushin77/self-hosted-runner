# Terraform variables for aws-spot self-hosted runners
# Ops: Update these values for your AWS account and deployment region

# VPC where runners will be deployed (must have internet access)
vpc_id = "vpc-0a1b2c3d4e5f6g7h8"

# Subnets for runner instances (should span multiple AZs for HA)
subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0fedcba987654321",
]

# EC2 key pair for SSH access (optional; comment out if not needed)
# key_name = "github-runners-key"

# Optional: ARN of Secrets Manager secret for webhook validation
# Leave empty to disable webhook secret management
webhook_secret_arn = ""

# Instance configuration (adjust as needed for your workload)
# instance_type = "t3.medium"  # see module defaults
# desired_capacity = 2
# min_size = 1
# max_size = 10
# enable_lifecycle_handler = true 
