// Terraform backend infrastructure (S3 + DynamoDB + KMS) for AWS
// This module creates an immutable, idempotent backend for Terraform state

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "project" {
  type    = string
  default = "self-hosted-runner"
}

variable "environment" {
  type    = string
  default = "phase-p4"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

// KMS key for state encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-terraform-state"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/${var.project}-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

// S3 bucket for state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project}-terraform-state-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project}-terraform-state"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

// DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project}-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }

  tags = {
    Name        = "${var.project}-terraform-locks"
    Environment = var.environment
  }
}

data "aws_caller_identity" "current" {}

output "s3_bucket_id" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket ID for Terraform state"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB table name for state locking"
}

output "kms_key_id" {
  value       = aws_kms_key.terraform_state.id
  description = "KMS key ID for state encryption"
}

output "kms_key_arn" {
  value       = aws_kms_key.terraform_state.arn
  description = "KMS key ARN for state encryption"
}
