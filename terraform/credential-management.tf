# ============================================================================
# NexusShield Portal MVP - Multi-Cloud Credential Management
# ============================================================================
# Implements GSM → Vault → KMS fallback chain for all credentials
# Supports: API keys, database passwords, TLS certificates, OAuth tokens
# Rotation: Automated every 6 hours (on-demand available)
# Audit: Immutable logging to Cloud Logging + GitHub audit trail
#
# REQUIREMENTS:
# - Google Cloud Secret Manager enabled
# - HashiCorp Vault cluster accessible
# - AWS credentials configured (tertiary fallback)
# - Service account with secret manager access
#
# DEPLOY: terraform apply -var-file=backend.conf.{staging|production}
# ============================================================================

terraform {
  required_providers {
    google       = { source = "hashicorp/google", version = "~> 5.0" }
    vault        = { source = "hashicorp/vault", version = "~> 3.0" }
    aws          = { source = "hashicorp/aws", version = "~> 5.0" }
    random       = { source = "hashicorp/random", version = "~> 3.0" }
    tls          = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

# ============================================================================
# PROVIDERS
# ============================================================================

provider "vault" {
  address = var.vault_address
  token   = var.vault_token

  auth_login {
    path      = "auth/gcp/login"
    method    = "POST"
    parameters = {
      jwt = data.google_client_config.current.access_token
      role = "portal-mvp-${var.environment}"
    }
    use_root_namespace = false
  }
}

provider "aws" {
  region = var.aws_region
  
  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/portal-mvp-terraform"
  }
}

# ============================================================================
# GOOGLE SECRET MANAGER - PRIMARY CREDENTIAL STORE
# ============================================================================

# Database Credentials (PostgreSQL)
resource "google_secret_manager_secret" "db_password" {
  secret_id = "portal-mvp-db-password-${var.environment}"
  
  labels = {
    environment = var.environment
    component   = "database"
    tier        = "primary"
    rotation    = "6h"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_iam_binding" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:portal-mvp-backend-${var.environment}@${var.gcp_project_id}.iam.gserviceaccount.com"
  ]
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result

  lifecycle {
    create_before_destroy = true
  }
}

# API Keys (External Services)
resource "google_secret_manager_secret" "api_keys" {
  secret_id = "portal-mvp-api-keys-${var.environment}"
  
  labels = {
    environment = var.environment
    component   = "api"
    tier        = "primary"
    rotation    = "6h"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_iam_binding" "api_keys_access" {
  secret_id = google_secret_manager_secret.api_keys.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:portal-mvp-backend-${var.environment}@${var.gcp_project_id}.iam.gserviceaccount.com"
  ]
}

resource "google_secret_manager_secret_version" "api_keys_version" {
  secret      = google_secret_manager_secret.api_keys.id
  secret_data = jsonencode({
    twilio_sid       = var.twilio_sid
    twilio_token     = var.twilio_token
    stripe_key       = var.stripe_key
    sendgrid_api_key = var.sendgrid_api_key
    google_oauth_id  = var.google_oauth_id
    google_oauth_secret = var.google_oauth_secret
  })

  lifecycle {
    create_before_destroy = true
  }
}

# OAuth Tokens (GitHub, Google, etc.)
resource "google_secret_manager_secret" "oauth_tokens" {
  secret_id = "portal-mvp-oauth-tokens-${var.environment}"
  
  labels = {
    environment = var.environment
    component   = "oauth"
    tier        = "primary"
    rotation    = "weekly"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_iam_binding" "oauth_tokens_access" {
  secret_id = google_secret_manager_secret.oauth_tokens.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${var.service_account_email}"
  ]
}

# TLS Certificates
resource "google_secret_manager_secret" "tls_certificate" {
  secret_id = "portal-mvp-tls-certificate-${var.environment}"
  
  labels = {
    environment = var.environment
    component   = "tls"
    tier        = "primary"
    rotation    = "quarterly"
  }

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_iam_binding" "tls_certificate_access" {
  secret_id = google_secret_manager_secret.tls_certificate.id
  role      = "roles/secretmanager.secretAccessor"
  members   = [
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:portal-mvp-api-gateway-${var.environment}@${var.gcp_project_id}.iam.gserviceaccount.com"
  ]
}

# ============================================================================
# HASHICORP VAULT - SECONDARY CREDENTIAL STORE & ROTATION ENGINE
# ============================================================================

# Vault Secret Backend for Portal MVP
resource "vault_mount" "portal_secrets" {
  path        = "secret/data/portal-mvp/${var.environment}"
  type        = "kv"
  description = "Portal MVP secrets for ${var.environment}"

  options = {
    version = "2"
  }
}

# Vault Policy for Service Accounts
resource "vault_policy" "portal_backend_policy" {
  name = "portal-backend-${var.environment}"

  policy = <<-EOT
    # Read database credentials
    path "secret/data/portal-mvp/${var.environment}/database/*" {
      capabilities = ["read", "list"]
    }

    # Read API keys
    path "secret/data/portal-mvp/${var.environment}/api-keys/*" {
      capabilities = ["read", "list"]
    }

    # Read OAuth tokens
    path "secret/data/portal-mvp/${var.environment}/oauth/*" {
      capabilities = ["read", "list"]
    }

    # Access database secret engine for dynamic credentials
    path "database/creds/portal-backend-${var.environment}" {
      capabilities = ["read"]
    }

    # SSH key signing
    path "ssh/sign/portal-${var.environment}" {
      capabilities = ["create", "update"]
    }

    # Lease renewal
    path "auth/token/renew-self" {
      capabilities = ["update"]
    }

    # Token lookup
    path "auth/token/lookup-self" {
      capabilities = ["read"]
    }
  EOT
}

# Database Secret Engine for Dynamic Credentials
resource "vault_database_secret_backend_connection" "portal_db" {
  backend       = "database"
  name          = "portal-${var.environment}"
  allowed_roles = ["portal-backend-${var.environment}", "portal-admin-${var.environment}"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.db_host}:5432/${var.db_name}"
  }

  username      = var.vault_db_admin_user
  password      = random_password.vault_db_admin_password.result
  verify_connection = true
}

resource "vault_database_secret_backend_role" "portal_backend_role" {
  backend             = vault_database_secret_backend_connection.portal_db.backend
  name                = "portal-backend-${var.environment}"
  db_name             = vault_database_secret_backend_connection.portal_db.name
  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"",
  ]
  default_ttl = "1h"
  max_ttl     = "24h"
}

# SSH Key Signing for Infrastructure Access
resource "vault_ssh_secret_backend" "portal_ssh" {
  path        = "ssh"
  description = "SSH key signing for Portal MVP"
}

resource "vault_ssh_secret_backend_role" "portal_ssh_role" {
  name                = "portal-${var.environment}"
  backend             = vault_ssh_secret_backend.portal_ssh.path
  allow_user_certificates = true
  allowed_users = "ubuntu,root,portal"
  default_ttl = "300s"
  max_ttl     = "3600s"
  key_type    = "ca"
}

# ============================================================================
# AWS KMS - TERTIARY CREDENTIAL STORE & DATA ENCRYPTION
# ============================================================================

# KMS Key for Data Encryption
resource "aws_kms_key" "portal_encryption_key" {
  description             = "KMS key for Portal MVP ${var.environment} encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name        = "portal-mvp-${var.environment}"
    Environment = var.environment
    Service     = "portal"
  }
}

resource "aws_kms_alias" "portal_encryption_key_alias" {
  name          = "alias/portal-mvp-${var.environment}"
  target_key_id = aws_kms_key.portal_encryption_key.key_id
}

# KMS Key Policy for Service Access
resource "aws_kms_key_policy" "portal_key_policy" {
  key_id = aws_kms_key.portal_encryption_key.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Portal Backend Service Access"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:role/portal-mvp-backend-${var.environment}"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs Encryption"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
          }
        }
      }
    ]
  })
}

# Secrets Manager for AWS-native credential storage
resource "aws_secretsmanager_secret" "portal_db_credentials" {
  name                    = "portal-mvp/${var.environment}/db-credentials"
  description             = "Database credentials for Portal MVP ${var.environment}"
  recovery_window_in_days = 30
  kms_key_id              = aws_kms_key.portal_encryption_key.id

  tags = {
    Environment = var.environment
    Service     = "portal"
  }
}

resource "aws_secretsmanager_secret_version" "portal_db_credentials_version" {
  secret_id = aws_secretsmanager_secret.portal_db_credentials.id
  secret_string = jsonencode({
    username = var.db_user
    password = random_password.db_password.result
    host     = var.db_host
    port     = 5432
    dbname   = var.db_name
  })
}

# ============================================================================
# CREDENTIAL ROTATION AUTOMATION
# ============================================================================

# Service Account for Rotation Automation
resource "google_service_account" "credential_rotator" {
  account_id   = "portal-mvp-credential-rotator-${var.environment}"
  display_name = "Portal MVP Credential Rotator (${var.environment})"
  description  = "Automated credential rotation for Portal MVP"
}

resource "google_project_iam_member" "credential_rotator_secrets" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.credential_rotator.email}"
}

resource "google_project_iam_member" "credential_rotator_kms" {
  project = var.gcp_project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.credential_rotator.email}"
}

# Cloud Scheduler Job - Rotate Credentials Every 6 Hours
resource "google_cloud_scheduler_job" "rotate_credentials" {
  name             = "portal-mvp-rotate-credentials-${var.environment}"
  description      = "Rotate Portal MVP credentials every 6 hours"
  schedule         = "0 */6 * * *"  # Every 6 hours
  time_zone        = "UTC"
  attempt_deadline = "600s"
  region           = var.gcp_region

  http_target {
    http_method = "POST"
    uri         = "https://${var.gcp_region}-${var.gcp_project_id}.cloudfunctions.net/portal-mvp-rotate-credentials"

    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.credential_rotator.email
      audience              = "https://${var.gcp_region}-${var.gcp_project_id}.cloudfunctions.net/portal-mvp-rotate-credentials"
    }
  }

  depends_on = [google_cloud_scheduler_job.rotate_credentials]
}

# ============================================================================
# ENCRYPTION & DATA PROTECTION
# ============================================================================

# Cloud KMS Keyring for GCP-native encryption
resource "google_kms_key_ring" "portal_keys" {
  name     = "portal-mvp-${var.environment}"
  location = var.gcp_region
}

# Master encryption key
resource "google_kms_crypto_key" "portal_master_key" {
  name                       = "portal-mvp-master-${var.environment}"
  key_ring                   = google_kms_key_ring.portal_keys.id
  rotation_period            = "2592000s"  # 30 days
  destroy_scheduled_duration = "86400s"    # 1 day

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }
}

# Database-specific encryption key
resource "google_kms_crypto_key" "db_encryption_key" {
  name                       = "portal-mvp-db-${var.environment}"
  key_ring                   = google_kms_key_ring.portal_keys.id
  rotation_period            = "7776000s"  # 90 days
  destroy_scheduled_duration = "86400s"

  version_template {
    algorithm = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }
}

# ============================================================================
# AUDIT LOGGING
# ============================================================================

# Cloud Audit Logs for credential access
resource "google_logging_project_sink" "credential_audit_logs" {
  name            = "portal-mvp-credential-audit-${var.environment}"
  destination     = "logging.googleapis.com/projects/${var.gcp_project_id}/logs/credential-audit"
  filter          = "resource.type=\"secretmanager.googleapis.com/Secret\" OR resource.type=\"secretmanager.googleapis.com/SecretVersion\""
  unique_writer_identity = true

  depends_on = [
    google_secret_manager_secret.db_password,
    google_secret_manager_secret.api_keys,
    google_secret_manager_secret.oauth_tokens,
    google_secret_manager_secret.tls_certificate
  ]
}

# ============================================================================
# RANDOM SECRETS GENERATION
# ============================================================================

resource "random_password" "db_password" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "vault_db_admin_password" {
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "credential_version" {
  byte_length = 16
  keepers = {
    rotation_timestamp = timestamp()
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "gsm_db_password_secret" {
  description = "Google Secret Manager secret ID for database password"
  value       = google_secret_manager_secret.db_password.id
  sensitive   = true
}

output "gsm_api_keys_secret" {
  description = "Google Secret Manager secret ID for API keys"
  value       = google_secret_manager_secret.api_keys.id
  sensitive   = true
}

output "vault_database_role" {
  description = "Vault database role for dynamic credentials"
  value       = vault_database_secret_backend_role.portal_backend_role.name
}

output "kms_key_id" {
  description = "AWS KMS key ID for encryption"
  value       = aws_kms_key.portal_encryption_key.id
}

output "gcp_kms_key_id" {
  description = "GCP Cloud KMS key ID for encryption"
  value       = google_kms_crypto_key.portal_master_key.id
}

output "credential_rotator_service_account" {
  description = "Service account email for credential rotation"
  value       = google_service_account.credential_rotator.email
}
