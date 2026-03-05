# Example tfvars for AWS spot example
# Replace the values below with your environment-specific IDs and keys.
vpc_id = "vpc-0123456789abcdef0"
subnet_ids = ["subnet-01234567", "subnet-89abcdef"]
instance_type = "t3.medium"
desired_capacity = 1
max_capacity = 2
key_name = "my-keypair"

# Optional: if you created the webhook secret in Secrets Manager, provide its ARN
# webhook_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:runner/drain-webhook-abc"

# Optional: if you want Terraform to create the secret (NOT recommended for sensitive values), enable and set the value below
# create_webhook_secret = false
# webhook_secret_value = "https://hooks.internal.example/drain"
