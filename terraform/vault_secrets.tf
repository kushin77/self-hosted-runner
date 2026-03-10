// Create Secret Manager secrets for Vault AppRole role_id and secret_id.
// The variable declarations for the secret names live in `cloud_run.tf`.

resource "random_password" "vault_role_id" {
  length  = 32
  special = true
}

resource "random_password" "vault_secret_id" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret" "vault_role" {
  count     = var.vault_role_id_secret_name != "" ? 1 : 0
  secret_id = var.vault_role_id_secret_name
  project   = var.gcp_project
  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

resource "google_secret_manager_secret" "vault_secret" {
  count     = var.vault_secret_id_secret_name != "" ? 1 : 0
  secret_id = var.vault_secret_id_secret_name
  project   = var.gcp_project
  replication {
    user_managed {
      replicas {
        location = var.gcp_region
      }
    }
  }
}

// Create ENABLED secret versions with auto-generated AppRole credentials
resource "google_secret_manager_secret_version" "vault_role_version" {
  count          = var.vault_role_id_secret_name != "" ? 1 : 0
  secret         = google_secret_manager_secret.vault_role[0].id
  secret_data    = random_password.vault_role_id.result
  enabled        = true
  depends_on     = [google_secret_manager_secret.vault_role]
}

resource "google_secret_manager_secret_version" "vault_secret_version" {
  count          = var.vault_secret_id_secret_name != "" ? 1 : 0
  secret         = google_secret_manager_secret.vault_secret[0].id
  secret_data    = random_password.vault_secret_id.result
  enabled        = true
  depends_on     = [google_secret_manager_secret.vault_secret]
}
