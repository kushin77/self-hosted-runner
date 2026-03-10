// Cloud Scheduler + Pub/Sub topics for cloud-native automation (optional)
// These resources create Pub/Sub topics and Scheduler jobs that publish messages.
// Deploy a Cloud Run service that subscribes to these topics to execute the tasks.

resource "google_pubsub_topic" "vault_sync" {
  name    = "vault-sync-topic"
  project = var.gcp_project
}

resource "google_pubsub_topic" "ephemeral_cleanup" {
  name    = "ephemeral-cleanup-topic"
  project = var.gcp_project
}

resource "google_cloud_scheduler_job" "vault_sync_job" {
  name     = "vault-sync-job"
  project  = var.gcp_project
  location = var.gcp_region

  pubsub_target {
    topic_name = google_pubsub_topic.vault_sync.id
    data       = base64encode("{\"action\":\"vault_sync\"}")
  }

  schedule = "*/15 * * * *" # every 15 minutes
  time_zone = "UTC"
}

resource "google_cloud_scheduler_job" "ephemeral_cleanup_job" {
  name     = "ephemeral-cleanup-job"
  project  = var.gcp_project
  location = var.gcp_region

  pubsub_target {
    topic_name = google_pubsub_topic.ephemeral_cleanup.id
    data       = base64encode("{\"action\":\"cleanup_ephemeral\"}")
  }

  schedule = "0 3 * * *" # daily at 03:00 UTC
  time_zone = "UTC"
}

output "scheduler_vault_topic" {
  value = google_pubsub_topic.vault_sync.name
}

output "scheduler_cleanup_topic" {
  value = google_pubsub_topic.ephemeral_cleanup.name
}
