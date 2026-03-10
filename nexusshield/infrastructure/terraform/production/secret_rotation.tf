###############################################################################
# Terraform: Secret rotation helper (enable rotation for managed secrets)
###############################################################################

resource "google_secret_manager_secret_rotation" "firestore_config_rotation" {
  secret = google_secret_manager_secret.firestore_config.id
  rotation {
    next_rotation_time = timeadd(timestamp(), "${var.secret_rotation_days}d")
  }
}

resource "null_resource" "rotation_note" {
  provisioner "local-exec" {
    command = "echo 'Secret rotation enabled for firestore_config (days=${var.secret_rotation_days})'"
  }
}
