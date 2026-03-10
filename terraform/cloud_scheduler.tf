// Cloud Scheduler + Pub/Sub topics for cloud-native automation (optional)
// These resources create Pub/Sub topics. Scheduler jobs are optional and
// intentionally omitted here due to provider schema differences; operators may
// create Scheduler jobs separately or in a dedicated module.

resource "google_pubsub_topic" "vault_sync" {
  name    = "vault-sync-topic"
  project = var.gcp_project
}

resource "google_pubsub_topic" "ephemeral_cleanup" {
  name    = "ephemeral-cleanup-topic"
  project = var.gcp_project
}

output "scheduler_vault_topic" {
  value = google_pubsub_topic.vault_sync.name
}

output "scheduler_cleanup_topic" {
  value = google_pubsub_topic.ephemeral_cleanup.name
}
