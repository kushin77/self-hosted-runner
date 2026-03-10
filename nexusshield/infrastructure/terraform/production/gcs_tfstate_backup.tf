###############################################################################
# Terraform: GCS bucket for Terraform state backups
###############################################################################

resource "google_storage_bucket" "tfstate_backups" {
  name     = "nexusshield-terraform-state-backups"
  location = var.gcp_region

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 90
    }
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }

  labels = merge(var.labels, { purpose = "tfstate-backup" })
}

# Optional: service account used by runner/backups (least-privilege)
resource "google_service_account" "tfstate_backup_sa" {
  account_id   = "nexusshield-tfstate-backup"
  display_name = "NexusShield TFState Backup Service Account"
}

resource "google_storage_bucket_iam_member" "backup_writer" {
  bucket = google_storage_bucket.tfstate_backups.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.tfstate_backup_sa.email}"
}
