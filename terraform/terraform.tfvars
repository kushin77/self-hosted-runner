# Temporary tfvars for dry-run
aws_region = "us-east-1"
vpc_id = "vpc-12345678"  # Placeholder - will fail but shows plan structure
subnet_ids = [
  "subnet-11111111",
  "subnet-22222222",
  "subnet-33333333"
]
cluster_name = "provisioner-redis-prod"
num_cache_nodes = 3
node_type = "cache.r6g.xlarge"
backup_retention_days = 30
