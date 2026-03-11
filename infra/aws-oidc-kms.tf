# AWS KMS setup for tertiary credential layer
# Purpose: Enable AWS KMS as fallback credential store (if Vault/GSM unavailable)
# AWS credentials fetched via GitHub OIDC → AWS STS (no long-lived keys)

# KMS key for credential encryption
resource "aws_kms_key" "secrets_orchestration" {
  description             = "KMS key for multi-layer secrets orchestration"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "secrets-orchestration"
    Environment = "production"
  }
}

# KMS key alias
resource "aws_kms_alias" "secrets_orchestration" {
  name          = "alias/secrets-orchestration"
  target_key_id = aws_kms_key.secrets_orchestration.key_id
}

# IAM role for GitHub OIDC
resource "aws_iam_role" "github_oidc" {
  name               = "github-oidc-role"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume.json

  tags = {
    Name = "github-oidc"
  }
}

# Trust policy for GitHub OIDC
data "aws_iam_policy_document" "github_oidc_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:kushin77/self-hosted-runner:ref:refs/heads/main"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]
  }
}

# Policy to use KMS key
resource "aws_iam_role_policy" "kms_access" {
  name   = "kms-access-policy"
  role   = aws_iam_role.github_oidc.id
  policy = data.aws_iam_policy_document.kms_access.json
}

data "aws_iam_policy_document" "kms_access" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.secrets_orchestration.arn]
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Outputs
output "aws_kms_key_id" {
  value       = aws_kms_key.secrets_orchestration.key_id
  description = "KMS key ID for secrets orchestration"
}

output "aws_iam_role_arn" {
  value       = aws_iam_role.github_oidc.arn
  description = "IAM role ARN for GitHub OIDC"
}
