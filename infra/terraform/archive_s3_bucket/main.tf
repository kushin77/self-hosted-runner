provider "aws" {
  region = var.region
}

# KMS key for encrypting archival objects
resource "aws_kms_key" "archive" {
  description             = "KMS key for milestone artifacts archival"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

# S3 bucket for immutable archival of audit artifacts
resource "aws_s3_bucket" "archive" {
  bucket = var.bucket_name
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = aws_kms_key.archive.arn
      }
    }
  }

  # Enable object-lock (bucket must be created with object lock enabled)
  object_lock_configuration {
    rule {
      default_retention {
        mode = "COMPLIANCE"
        days = var.retention_days
      }
    }
  }
  lifecycle {
    ignore_changes = [
      object_lock_configuration,
    ]
  }
}

resource "aws_s3_bucket_public_access_block" "archive_block" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Example IAM policy for a runner that needs to upload objects
data "aws_iam_policy_document" "uploader" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.archive.arn,
      "${aws_s3_bucket.archive.arn}/*"
    ]
  }

  statement {
    actions = ["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey"]
    resources = [aws_kms_key.archive.arn]
  }
}

output "bucket_name" {
  value = aws_s3_bucket.archive.bucket
}

output "kms_key_arn" {
  value = aws_kms_key.archive.arn
}
