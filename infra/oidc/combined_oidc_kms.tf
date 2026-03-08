terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" { type = string, default = "us-east-1" }
variable "github_owner" { type = string }
variable "github_repo" { type = string }
variable "branch" { type = string, default = "main" }
variable "role_name" { type = string, default = "github-actions-oidc-role" }
variable "kms_alias" { type = string, default = "alias/ci-secrets-key" }

provider "aws" { region = var.aws_region }

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:ref:refs/heads/${var.branch}"]
    }
  }
}

resource "aws_iam_role" "github_actions_role" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_kms_key" "ci_key" {
  description             = "KMS key for CI ephemeral secrets"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "ci_key_alias" {
  name          = var.kms_alias
  target_key_id = aws_kms_key.ci_key.key_id
}

data "aws_iam_policy_document" "kms_access" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = [aws_kms_key.ci_key.arn]
  }
}

resource "aws_iam_policy" "ci_kms_policy" {
  name   = "ci-kms-access"
  policy = data.aws_iam_policy_document.kms_access.json
}

resource "aws_iam_role_policy_attachment" "attach_kms" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.ci_kms_policy.arn
}

output "role_arn" {
  value = aws_iam_role.github_actions_role.arn
}

output "kms_key_id" {
  value = aws_kms_key.ci_key.key_id
}
