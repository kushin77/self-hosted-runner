variable "role_name" {
  type    = string
  default = "github-actions-oidc-role"
}

variable "kms_key_arn" {
  type = string
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
    resources = [var.kms_key_arn]
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
