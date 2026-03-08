variable "key_alias" {
  type    = string
  default = "alias/ci-secrets-key"
}

resource "aws_kms_key" "ci_key" {
  description             = "KMS key for CI ephemeral secrets and state encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "ci_key_alias" {
  name          = var.key_alias
  target_key_id = aws_kms_key.ci_key.key_id
}

output "kms_key_id" {
  value = aws_kms_key.ci_key.key_id
}
