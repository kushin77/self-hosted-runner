# Production-grade Redis (Elasticache) for Provisioner Queue
resource "aws_elasticache_cluster" "redis_queue" {
  cluster_id           = "${var.project_name}-redis-${var.environment}"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnets.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}

resource "aws_elasticache_subnet_group" "redis_subnets" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_security_group" "redis_sg" {
  name        = "${var.project_name}-redis-sg"
  description = "Allow Redis traffic from services"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Vault AppRole Policy Template
resource "local_file" "vault_provisioner_policy" {
  filename = "config/vault/provisioner-policy.hcl"
  content  = <<-EOT
    path "secret/data/runners/*" {
      capabilities = ["read", "list"]
    }
    path "auth/approle/login" {
      capabilities = ["create", "read"]
    }
  EOT
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis_queue.cache_nodes[0].address
}
