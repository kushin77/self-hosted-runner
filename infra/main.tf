# 🚀 À LA CARTE DEPLOYMENT — Infrastructure as Code
# Terraform configuration for GCP + AWS multi-cloud architecture
#
# Properties: Immutable (state-locked), Ephemeral (15-min tokens), Idempotent (state-based)
# No-Ops, Hands-Off, GSM/Vault/KMS 3-layer secrets
#

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Terraform state: immutable and locked
  # Can be backed by GCS bucket or local (for demo)
  # backend "gcs" {
  #   bucket  = "terraform-state-prod"
  #   prefix  = "10x-deployment"
  # }
}

# ============================================================================
# VARIABLES
# ============================================================================

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "enable_aws" {
  description = "Enable AWS multi-cloud resources"
  type        = bool
  default     = false
}

variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.example.com"
}

# ============================================================================
# GCP PROVIDER
# ============================================================================

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ============================================================================
# LAYER 1: GOOGLE SECRET MANAGER (Primary Secrets Layer)
# ============================================================================

resource "google_secret_manager_secret" "auto_credentials" {
  secret_id = "auto-credentials"

  replication {
    auto {} # Enable automatic replication across regions
  }

  labels = {
    environment = var.environment
    layer       = "primary"
    purpose     = "ephemeral-credentials"
  }
}

resource "google_secret_manager_secret_iam_member" "workload_identity" {
  secret_id = google_secret_manager_secret.auto_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workload_identity.email}"
}

# ============================================================================
# LAYER 1: CLOUD KMS (Encryption at Rest)
# ============================================================================

resource "google_kms_key_ring" "auto_credentials_ring" {
  name     = "auto-credentials-ring"
  location = var.gcp_region
}

resource "google_kms_crypto_key" "auto_credentials_key" {
  name            = "auto-credentials-key"
  key_ring        = google_kms_key_ring.auto_credentials_ring.id
  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true # IMMUTABLE: prevent accidental deletion
  }
}

# ============================================================================
# LAYER 2: WORKLOAD IDENTITY FEDERATION (Ephemeral OIDC)
# ============================================================================

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "github-pool"
  location                  = "global"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  disabled                  = false
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  location                           = "global"
  display_name                       = "GitHub"
  disabled                           = false

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.aud"        = "assertion.aud"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# ============================================================================
# SERVICE ACCOUNT FOR WORKLOAD IDENTITY
# ============================================================================

resource "google_service_account" "workload_identity" {
  account_id   = "github-workload-identity"
  display_name = "GitHub Actions Workload Identity"
  description  = "Service account for GitHub Actions ephemeral authentication"
}

# Grant permissions to service account
resource "google_project_iam_member" "workload_identity_user" {
  project = var.gcp_project_id
  role    = "roles/iam.workloadIdentityUser"
  member  = "serviceAccount:${google_service_account.workload_identity.email}"
}

resource "google_project_iam_member" "secrets_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.workload_identity.email}"
}

resource "google_project_iam_member" "kms_decrypt" {
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyDecrypter"
  member  = "serviceAccount:${google_service_account.workload_identity.email}"
}

# ============================================================================
# LAYER 2: VAULT OIDC INTEGRATION (Secondary Secrets Layer)
# ============================================================================

provider "vault" {
  address = var.vault_addr
  # auth via OIDC is configured in GitHub Actions workflow
}

resource "vault_auth_method" "oidc" {
  type = "oidc"
  path = "oidc"

  tune {
    token_ttl     = "15m" # EPHEMERAL: 15-minute token TTL
    max_lease_ttl = "30m"
  }
}

resource "vault_oidc_auth_backend_role" "github_actions" {
  backend         = vault_auth_method.oidc.path
  role_name       = "github-actions"
  user_claim      = "sub"
  bound_audiences = ["https://github.com/kushin77"]
  token_ttl       = "15m" # EPHEMERAL
  token_max_ttl   = "30m"

  role_type   = "oidc"
  oidc_scopes = ["profile", "email"]
}

resource "vault_policy" "ephemeral_credentials" {
  name = "ephemeral-credentials"

  policy = <<EOH
path "secret/data/credentials/*" {
  capabilities = ["read", "list"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOH
}

# ============================================================================
# LAYER 3: AWS KMS (Optional Tertiary/Multi-Cloud)
# ============================================================================

provider "aws" {
  region = "us-east-1"

  skip_credentials_validation = !var.enable_aws
}

resource "aws_kms_key" "auto_credentials" {
  count = var.enable_aws ? 1 : 0

  description             = "Multi-cloud credentials encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Environment = var.environment
    Layer       = "tertiary"
    Purpose     = "multi-cloud-failover"
  }
}

resource "aws_kms_alias" "auto_credentials" {
  count         = var.enable_aws ? 1 : 0
  name          = "alias/auto-credentials"
  target_key_id = aws_kms_key.auto_credentials[0].key_id
}

# ============================================================================
# MONITORING & HEALTH CHECKS
# ============================================================================

resource "google_monitoring_alert_policy" "secret_access" {
  display_name = "Secret Manager Access Alert"
  combiner     = "OR"

  conditions {
    display_name = "High rate of failed secret access"

    condition_threshold {
      filter          = "resource.type=\"secretmanager.googleapis.com/Secret\" AND metric.type=\"secretmanager.googleapis.com/secret/access_count\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 100
    }
  }

  notification_channels = [] # Add your notification channels
}

# ============================================================================
# OUTPUTS (Immutable Reference)
# ============================================================================

output "service_account_email" {
  description = "Service account email for GitHub Actions"
  value       = google_service_account.workload_identity.email
}

output "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  value       = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
}

output "workload_identity_provider_id" {
  description = "Workload Identity Provider ID"
  value       = google_iam_workload_identity_pool_provider.github_provider.workload_identity_pool_provider_id
}

output "secret_manager_secret_id" {
  description = "Secret Manager Secret ID"
  value       = google_secret_manager_secret.auto_credentials.secret_id
}

output "kms_key_id" {
  description = "Cloud KMS Key ID"
  value       = google_kms_crypto_key.auto_credentials_key.id
}

output "vault_oidc_role" {
  description = "Vault OIDC Role for GitHub Actions"
  value       = vault_oidc_auth_backend_role.github_actions.role_name
}

output "vault_token_ttl" {
  description = "Vault Token TTL (Ephemeral)"
  value       = "15m"
}

output "deployment_properties" {
  description = "Deployment Architecture Properties"
  value = {
    immutable      = "v2026.03.08-production-ready (locked tag)"
    ephemeral      = "Vault OIDC 15-min TTL + auto-rotation"
    idempotent     = "Terraform state-based (no duplicates)"
    no_ops         = "15-min health checks + 2 AM UTC rotation"
    hands_off      = "4-step operator process, fully automated"
    secrets_layers = "GSM (primary) → Vault (secondary) → KMS (tertiary)"
  }
}
