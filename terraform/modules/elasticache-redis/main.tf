# ElastiCache Redis for Provisioner-Worker
# Production-grade Redis cluster with encryption, backups, and monitoring

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.35"
    }
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for ElastiCache cluster"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for ElastiCache (multiple AZs recommended)"
  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet required"
  }
}

variable "cluster_name" {
  type        = string
  description = "Name of the ElastiCache cluster"
  default     = "provisioner-redis-prod"
}

variable "engine_version" {
  type        = string
  description = "Redis engine version"
  default     = "7.0"
}

variable "node_type" {
  type        = string
  description = "ElastiCache node type"
  default     = "cache.r6g.xlarge" # Graviton2, 26GB memory, good for high throughput
}

variable "num_cache_nodes" {
  type        = number
  description = "Number of cache nodes (1 for single-node, 2+ for replication)"
  default     = 3
  validation {
    condition     = var.num_cache_nodes >= 1
    error_message = "Minimum 1 node required"
  }
}

variable "automatic_failover_enabled" {
  type        = bool
  description = "Enable automatic failover (requires 2+ nodes)"
  default     = true
}

variable "multi_az_enabled" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = true
}

variable "backup_retention_days" {
  type        = number
  description = "Number of days to retain backups"
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days"
  }
}

variable "snapshot_retention_limit" {
  type        = number
  description = "Number of automatic snapshots to retain"
  default     = 5
}

variable "snapshot_window" {
  type        = string
  description = "Daily time window for automatic snapshots (UTC)"
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  type        = string
  description = "Weekly maintenance window (always use UTC, e.g., sun:04:00-sun:05:00)"
  default     = "sun:04:00-sun:05:00"
}

variable "enable_encryption_at_rest" {
  type        = bool
  description = "Enable encryption at rest with AWS KMS"
  default     = true
}

variable "enable_encryption_in_transit" {
  type        = bool
  description = "Enable encryption in transit (TLS)"
  default     = true
}

variable "auth_token_enabled" {
  type        = bool
  description = "Enable AUTH token for additional security"
  default     = true
}

variable "auth_token" {
  type        = string
  description = "AUTH token (32-128 alphanumeric characters, or empty to generate)"
  default     = ""
  sensitive   = true
}

variable "allowed_security_groups" {
  type        = list(string)
  description = "Security groups that can access Redis"
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks that can access Redis"
  default     = []
}

variable "parameter_group_family" {
  type        = string
  description = "Redis parameter group family"
  default     = "redis7"
}

variable "tags" {
  type        = map(string)
  description = "Common tags for all resources"
  default = {
    Project     = "elevatediq-runners"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# Generate or use provided AUTH token
locals {
  auth_token = var.auth_token_enabled ? (
    var.auth_token != "" ? var.auth_token : random_password.redis_auth.result
  ) : null
}

# Create random AUTH token if not provided
resource "random_password" "redis_auth" {
  count   = var.auth_token_enabled && var.auth_token == "" ? 1 : 0
  length  = 48
  special = true
  # ElastiCache requires tokens to be 32-128 alphanumeric, so strip special chars
  override_special = ""
}

# KMS key for encryption
resource "aws_kms_key" "redis" {
  count                   = var.enable_encryption_at_rest ? 1 : 0
  description             = "KMS key for ElastiCache encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-key"
  })
}

resource "aws_kms_alias" "redis" {
  count         = var.enable_encryption_at_rest ? 1 : 0
  name          = "alias/${var.cluster_name}-key"
  target_key_id = aws_kms_key.redis[0].key_id
}

# Subnet group for cluster placement
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-subnet-group"
  })
}

# Security group for Redis
resource "aws_security_group" "redis" {
  name_prefix = "${var.cluster_name}-"
  vpc_id      = var.vpc_id

  # Ingress: from allowed security groups
  dynamic "ingress" {
    for_each = var.allowed_security_groups
    content {
      from_port       = 6379
      to_port         = 6380
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Redis from ${ingress.value}"
    }
  }

  # Ingress: from allowed CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 6379
      to_port     = 6380
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Redis from ${ingress.value}"
    }
  }

  # Egress: allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Custom parameter group for optimization
resource "aws_elasticache_parameter_group" "redis" {
  family = var.parameter_group_family
  name   = "${var.cluster_name}-params"

  # Provisioner-worker optimizations
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru" # Evict any key using LRU when max memory reached
  }

  parameter {
    name  = "timeout"
    value = "300" # Idle client timeout (prevent hanging connections)
  }

  parameter {
    name  = "tcp-keepalive"
    value = "60" # Enable TCP keepalive to detect dead clients
  }

  parameter {
    name  = "appendonly"
    value = var.backup_retention_days > 0 ? "yes" : "no"
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-params"
  })
}

# ElastiCache cluster
resource "aws_elasticache_replication_group" "redis" {
  replication_group_description = "Redis cluster for provisioner-worker job queue (${var.cluster_name})"
  engine                        = "redis"
  engine_version               = var.engine_version
  node_type                     = var.node_type
  num_cache_clusters           = var.num_cache_nodes
  parameter_group_name          = aws_elasticache_parameter_group.redis.name
  port                          = 6379
  
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis.id]
  
  # Automatic failover and Multi-AZ
  automatic_failover_enabled    = var.automatic_failover_enabled && var.num_cache_nodes > 1 ? true : false
  multi_az_enabled              = var.multi_az_enabled && var.num_cache_nodes > 1 ? true : false
  
  # Backups and snapshots
  snapshot_retention_limit      = var.snapshot_retention_limit
  snapshot_window               = var.snapshot_window
  maintenance_window            = var.maintenance_window
  notification_topic_arn        = null # Can add SNS topic for notifications
  
  # Security: encryption and AUTH
  at_rest_encryption_enabled    = var.enable_encryption_at_rest
  kms_key_id                    = var.enable_encryption_at_rest ? aws_kms_key.redis[0].arn : null
  transit_encryption_enabled    = var.enable_encryption_in_transit
  transit_encryption_mode       = var.enable_encryption_in_transit ? "preferred" : null
  auth_token                    = local.auth_token
  
  # Logging
  log_delivery_configuration {
    destination      = "" # Can add CloudWatch log group
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
    enabled          = false # Enable if CloudWatch logs configured
  }

  # Automatic minor patch updates
  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = merge(var.tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_elasticache_parameter_group.redis,
    aws_elasticache_subnet_group.redis
  ]
}

# Output values
output "redis_endpoint" {
  description = "Redis cluster endpoint (primary address)"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_url" {
  description = "Complete Redis URL for connection (without AUTH token)"
  value       = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

output "redis_url_with_auth" {
  description = "Complete Redis URL with AUTH (use in secrets)"
  value       = var.auth_token_enabled ? "redis://default:${local.auth_token}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}" : null
  sensitive   = true
}

output "redis_auth_token" {
  description = "AUTH token (use in PROVISIONER_REDIS_AUTH secret)"
  value       = local.auth_token
  sensitive   = true
}

output "cluster_id" {
  description = "Replication group ID"
  value       = aws_elasticache_replication_group.redis.id
}

output "security_group_id" {
  description = "Security group ID for Redis cluster"
  value       = aws_security_group.redis.id
}

output "kms_key_id" {
  description = "KMS key ID for encrypted backups"
  value       = var.enable_encryption_at_rest ? aws_kms_key.redis[0].id : null
}
