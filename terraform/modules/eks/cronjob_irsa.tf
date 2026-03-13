resource "aws_iam_role" "cronjob_role" {
  name = "${var.cluster_name}-cronjob-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:cron-jobs:milestone-organizer"
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# S3 access for CronJob to archive data
resource "aws_iam_role_policy" "cronjob_s3_access" {
  name = "${var.cluster_name}-cronjob-s3-access"
  role = aws_iam_role.cronjob_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Sid    = "S3BucketVersioning"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning"
        ]
        Resource = var.s3_bucket_arn
      }
    ]
  })
}

# Secrets Manager access for CronJob
resource "aws_iam_role_policy" "cronjob_secrets_access" {
  name = "${var.cluster_name}-cronjob-secrets-access"
  role = aws_iam_role.cronjob_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_arns
      }
    ]
  })
}

# CloudWatch Logs for CronJob
resource "aws_iam_role_policy" "cronjob_logs_access" {
  name = "${var.cluster_name}-cronjob-logs-access"
  role = aws_iam_role.cronjob_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/eks/*"
      }
    ]
  })
}

output "cronjob_role_arn" {
  description = "ARN of the CronJob IRSA role"
  value       = aws_iam_role.cronjob_role.arn
}

output "cronjob_role_name" {
  description = "Name of the CronJob IRSA role"
  value       = aws_iam_role.cronjob_role.name
}
