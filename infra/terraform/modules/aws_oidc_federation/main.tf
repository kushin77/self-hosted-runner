/**
 * AWS OIDC Federation Module
 * Enables cross-account credential exchange via GitHub Actions OIDC tokens
 * Replaces long-lived AWS Access Keys with temporary STS assume-role credentials
 * 
 * Properties: Immutable (IAM policies versioned), Idempotent (no resource overwrites), Ephemeral (credentials expire)
 */

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# AWS OIDC Provider
# ============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  
  # GitHub's OIDC certificate thumbprint (static, verified from GitHub JWKS)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = merge(
    var.tags,
    { name = "github-oidc" }
  )

  lifecycle {
    # Idempotent: re-applying doesn't recreate
    ignore_changes = [client_id_list]
  }
}

# ============================================================================
# IAM Role for GitHub Actions OIDC
# ============================================================================
resource "aws_iam_role" "github_oidc" {
  name        = var.role_name
  description = "IAM role for GitHub Actions OIDC federation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    { name = var.role_name }
  )

  lifecycle {
    # Idempotent policy updates
    ignore_changes = [assume_role_policy]
  }
}

# ============================================================================
# Policies for the OIDC Role (minimal, scoped permissions)
# ============================================================================

# Allow KMS operations for credential envelope encryption
resource "aws_iam_role_policy" "kms_operations" {
  name = "${var.role_name}-kms-operations"
  role = aws_iam_role.github_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "kms.${var.aws_region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# Allow Secrets Manager read for credential rotation
resource "aws_iam_role_policy" "secrets_manager" {
  name = "${var.role_name}-secrets-read"
  role = aws_iam_role.github_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:*"
        Condition = {
          StringLike = {
            "secretsmanager:ResourceTag/managed_by" = "terraform"
          }
        }
      }
    ]
  })
}

# Allow STS AssumeRole chaining (for cross-account access)
resource "aws_iam_role_policy" "assume_role_chaining" {
  name = "${var.role_name}-assume-role-chaining"
  role = aws_iam_role.github_oidc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:GetCallerIdentity"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/github-*"
      }
    ]
  })
}
