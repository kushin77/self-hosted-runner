# Terraform variables for runner + elasticache deployment
aws_region       = "us-east-1"
project_id       = "gcp-eiq"
github_owner     = "kushin77"
github_repo      = "self-hosted-runner"
runner_token     = "ghp_dummy_token_for_testing"
vpc_id           = "vpc-12345678"
subnet_ids       = ["subnet-11111111", "subnet-22222222", "subnet-33333333"]
cluster_name     = "provisioner-redis-prod"
num_cache_nodes  = 3
node_type        = "cache.r6g.xlarge"
backup_retention_days = 30
