# Phase 2 Blockers — Infrastructure as Code (Terraform)
# Automatically configures: GCP WIF, AWS OIDC, Vault AppRole
# Idempotent | Immutable | No-Ops

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = "us-central1"
}

provider "aws" {
  region = "us-east-1"
}

provider "vault" {
  address = var.vault_addr
}

# ============================================================================
# Variables (Can be set via: terraform apply -var="..." or terraform.tfvars)
# ============================================================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  default     = ""
}

variable "vault_addr" {
  description = "Vault Address"
  type        = string
  default     = ""
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "kushin77"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "self-hosted-runner"
}

variable "vault_namespace" {
  description = "Vault Namespace"
  type        = string
  default     = "admin"
}

# ============================================================================
# GCP: Workload Identity Pool + OIDC Provider
# Issue #2158: Unblock GCP WIF Setup
# ============================================================================

# Create Workload Identity Pool
resource "google_iam_workload_identity_pool" "github_actions" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  workload_identity_pool_id = "github-actions"
  location                  = "global"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions"
  disabled                  = false

  depends_on = [
    google_project_service.required_services_gcp
  ]
}

# Create OIDC Provider
resource "google_iam_workload_identity_pool_provider" "github" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  workload_identity_pool_id           = google_iam_workload_identity_pool.github_actions[0].workload_identity_pool_id
  workload_identity_pool_provider_id  = "github"
  location                            = "global"
  display_name                        = "GitHub"
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.repository"       = "assertion.repository"
  }
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"
  
  attribute_value_type = "EXPRESSION"
  
  issuer_uri = "https://token.actions.githubusercontent.com"
}

# Service Account for GitHub Actions
resource "google_service_account" "github_actions" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  account_id   = "github-actions"
  display_name = "GitHub Actions"
  description  = "Service account for GitHub Actions OIDC"
}

# Grant Workload Identity User role
resource "google_service_account_iam_member" "workload_identity_user" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  service_account_id = google_service_account.github_actions[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_client_config.current.project}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions[0].workload_identity_pool_id}/attribute.repository/${var.github_owner}/${var.github_repo}"
}

# Grant necessary roles to service account
resource "google_project_iam_member" "github_actions_viewer" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  project = data.google_client_config.current.project
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.github_actions[0].email}"
}

resource "google_project_iam_member" "github_actions_token_creator" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  project = data.google_client_config.current.project
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_service_account.github_actions[0].email}"
}

# Enable required APIs
resource "google_project_service" "required_services_gcp" {
  count = var.gcp_project_id != "" ? 1 : 0
  
  project = data.google_client_config.current.project
  service = each.key

  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com"
  ])
}

# ============================================================================
# AWS: OIDC Provider + IAM Role
# Issue #2159: Unblock AWS OIDC Provider
# ============================================================================

# Create OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  count = var.aws_account_id != "" ? 1 : 0
  
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  
  tags = {
    Name        = "GitHub Actions"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Get GitHub Actions certificate thumbprint
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# Create IAM role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  count = var.aws_account_id != "" ? 1 : 0
  
  name               = "github-actions-oidc"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_owner}/${var.github_repo}:*"
          }
        }
      }
    ]
  })
  
  tags = {
    Name        = "GitHub Actions OIDC"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Inline policy for KMS, Secrets Manager, CloudTrail
resource "aws_iam_role_policy" "github_actions" {
  count = var.aws_account_id != "" ? 1 : 0
  
  name   = "github-actions-policy"
  role   = aws_iam_role.github_actions[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:GetKeyRotationStatus",
          "kms:EnableKeyRotation",
          "kms:ListKeys"
        ]
        Resource = "arn:aws:kms:*:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "sts.amazonaws.com"
          }
        }
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:RotateSecret"
        ]
        Resource = "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:github-actions-*"
      },
      {
        Sid    = "CloudTrailAccess"
        Effect = "Allow"
        Action = [
          "cloudtrail:LookupEvents",
          "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrailStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "STSAccess"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole",
          "sts:AssumeRoleWithWebIdentity"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
      }
    ]
  })
}

# Create KMS master key for credential encryption
resource "aws_kms_key" "github_actions_credentials" {
  count = var.aws_account_id != "" ? 1 : 0
  
  description             = "KMS key for GitHub Actions credential encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
  
  tags = {
    Name        = "GitHub Actions Credentials"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "github_actions_credentials" {
  count = var.aws_account_id != "" ? 1 : 0
  
  name          = "alias/github-actions-credentials"
  target_key_id = aws_kms_key.github_actions_credentials[0].key_id
}

# Allow GitHub Actions role to use KMS key
resource "aws_kms_key_policy" "github_actions" {
  count = var.aws_account_id != "" ? 1 : 0
  
  key_id = aws_kms_key.github_actions_credentials[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow GitHub Actions Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.github_actions[0].arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:GetKeyRotationStatus",
          "kms:EnableKeyRotation"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# Vault: AppRole Auth + Policies
# Issue #2160: Unblock Vault AppRole Setup
# ============================================================================

# Enable AppRole auth method
resource "vault_auth_backend" "approle" {
  count = var.vault_addr != "" ? 1 : 0
  
  type = "approle"
  path = "approle"
}

# Create AppRoles for different services
resource "vault_approle_auth_backend_role" "github_actions_roles" {
  for_each = var.vault_addr != "" ? toset(["deployment-automation", "credential-rotation", "observability"]) : toset([])
  
  backend            = vault_auth_backend.approle[0].path
  role_name          = each.key
  bind_secret_id     = true
  secret_id_ttl      = 2592000  # 30 days
  secret_id_num_uses = 1000
  token_ttl          = 3600     # 1 hour
  token_max_ttl      = 86400    # 24 hours
  policies           = ["default", "github-actions"]
}

# Get role IDs
resource "vault_approle_auth_backend_role_secret_id" "github_actions" {
  for_each = var.vault_addr != "" ? toset(["deployment-automation", "credential-rotation", "observability"]) : toset([])
  
  backend   = vault_auth_backend.approle[0].path
  role_name = vault_approle_auth_backend_role.github_actions_roles[each.key].role_name
}

# Vault policy for GitHub Actions
resource "vault_policy" "github_actions" {
  count = var.vault_addr != "" ? 1 : 0
  
  name = "github-actions"
  
  policy = <<-EOT
    path "auth/approle/role/*/secret-id" {
      capabilities = ["update"]
    }
    path "secret/data/github/*" {
      capabilities = ["read", "list"]
    }
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }
    path "sys/leases/renew" {
      capabilities = ["update"]
    }
  EOT
}

# ============================================================================
# Data Sources
# ============================================================================

data "google_client_config" "current" {}

data "aws_caller_identity" "current" {}

# ============================================================================
# Outputs
# ============================================================================

output "gcp_workload_identity_pool" {
  description = "GCP Workload Identity Pool resource name"
  value = try(
    google_iam_workload_identity_pool.github_actions[0].name,
    "Not configured (set gcp_project_id)"
  )
}

output "gcp_service_account_email" {
  description = "GCP Service Account email"
  value = try(
    google_service_account.github_actions[0].email,
    "Not configured (set gcp_project_id)"
  )
}

output "aws_oidc_provider_arn" {
  description = "AWS OIDC Provider ARN"
  value = try(
    aws_iam_openid_connect_provider.github[0].arn,
    "Not configured (set aws_account_id)"
  )
}

output "aws_iam_role_arn" {
  description = "AWS IAM Role ARN for GitHub Actions"
  value = try(
    aws_iam_role.github_actions[0].arn,
    "Not configured (set aws_account_id)"
  )
}

output "aws_kms_key_id" {
  description = "AWS KMS Key ID for credential encryption"
  value = try(
    aws_kms_key.github_actions_credentials[0].id,
    "Not configured (set aws_account_id)"
  )
}

output "vault_approle_backend_path" {
  description = "Vault AppRole auth backend path"
  value = try(
    vault_auth_backend.approle[0].path,
    "Not configured (set vault_addr)"
  )
}
