/**
 * Storage/GCS Module - Main Configuration
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ============================================================================
# TERRAFORM STATE BACKEND
# ============================================================================

resource "google_storage_bucket" "terraform_state" {
  project  = var.project_id
  name     = "${var.service_name}-terraform-state-${var.environment}-${data.google_client_config.current.project}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.environment == "dev" ? true : false

  versioning {
    enabled = var.enable_versioning
  }

  encryption {
    default_kms_key_name = var.enable_encryption ? google_kms_crypto_key.storage.id : null
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions         = 3
      days_since_noncurrent_time = 60
    }
  }

  logging {
    log_bucket        = google_storage_bucket.audit_logs.name
    log_object_prefix = "terraform-state/"
  }

  labels = merge(var.labels, { purpose = "terraform-state" })
}

# ============================================================================
# CONTAINER ARTIFACTS
# ============================================================================

resource "google_storage_bucket" "artifacts" {
  project  = var.project_id
  name     = "${var.service_name}-artifacts-${var.environment}-${data.google_client_config.current.project}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.environment == "dev" ? true : false

  versioning {
    enabled = var.enable_versioning
  }

  encryption {
    default_kms_key_name = var.enable_encryption ? google_kms_crypto_key.storage.id : null
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.retention_days
    }
  }

  logging {
    log_bucket        = google_storage_bucket.audit_logs.name
    log_object_prefix = "artifacts/"
  }

  labels = merge(var.labels, { purpose = "container-artifacts" })
}

# ============================================================================
# DATABASE BACKUPS
# ============================================================================

resource "google_storage_bucket" "backups" {
  project  = var.project_id
  name     = "${var.service_name}-backups-${var.environment}-${data.google_client_config.current.project}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.environment == "dev" ? true : false

  versioning {
    enabled = var.enable_versioning
  }

  encryption {
    default_kms_key_name = var.enable_encryption ? google_kms_crypto_key.storage.id : null
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.backup_retention_days
    }
  }

  logging {
    log_bucket        = google_storage_bucket.audit_logs.name
    log_object_prefix = "backups/"
  }

  labels = merge(var.labels, { purpose = "database-backups" })
}

# ============================================================================
# AUDIT LOGS STORAGE
# ============================================================================

resource "google_storage_bucket" "audit_logs" {
  project  = var.project_id
  name     = "${var.service_name}-audit-logs-${var.environment}-${data.google_client_config.current.project}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = var.public_access_prevention
  force_destroy               = var.environment == "dev" ? true : false

  versioning {
    enabled = var.enable_versioning
  }

  encryption {
    default_kms_key_name = var.enable_encryption ? google_kms_crypto_key.storage.id : null
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.audit_logs_retention_days
    }
  }

  labels = merge(var.labels, { purpose = "audit-logs" })
}

# ============================================================================
# KMS ENCRYPTION
# ============================================================================

resource "google_kms_key_ring" "storage" {
  project  = var.project_id
  name     = "${var.service_name}-storage-keyring-${var.environment}"
  location = var.region
}

resource "google_kms_crypto_key" "storage" {
  name            = "${var.service_name}-storage-key-${var.environment}"
  key_ring        = google_kms_key_ring.storage.id
  rotation_period = "7776000s" # 90 days
  labels          = var.labels
}

# ============================================================================
# BUCKET IAM BINDINGS
# ============================================================================

resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.terraform_service_account_email}"
}

resource "google_storage_bucket_iam_member" "artifacts_writer" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.service_account_email}"
}

resource "google_storage_bucket_iam_member" "artifacts_reader" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${var.service_account_email}"
}

resource "google_storage_bucket_iam_member" "backups_writer" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.service_account_email}"
}

resource "google_storage_bucket_iam_member" "audit_logs_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${var.service_account_email}"
}

# ============================================================================
# KMS IAM BINDINGS
# ============================================================================

resource "google_kms_crypto_key_iam_member" "terraform_decrypt" {
  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${var.terraform_service_account_email}"
}

resource "google_kms_crypto_key_iam_member" "terraform_encrypt" {
  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyEncrypter"
  member        = "serviceAccount:${var.terraform_service_account_email}"
}

resource "google_kms_crypto_key_iam_member" "service_account_decrypt" {
  crypto_key_id = google_kms_crypto_key.storage.id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${var.service_account_email}"
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "google_client_config" "current" {}
