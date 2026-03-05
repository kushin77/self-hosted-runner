# Placeholder terraform.tfvars for aws-spot example
# Replace the values below with real IDs from your AWS account before running `terraform plan`.

vpc_id = "REPLACE_ME_VPC_ID"

subnet_ids = [
  "REPLACE_ME_SUBNET_ID_1",
  "REPLACE_ME_SUBNET_ID_2",
  "REPLACE_ME_SUBNET_ID_3",
]

# Optional: ARN of a Secrets Manager secret containing the webhook secret
webhook_secret_arn = "" 
