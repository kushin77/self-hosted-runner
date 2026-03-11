variable "project" { type = string }
variable "region" { type = string }
variable "function_source_dir" { type = string }
variable "function_name" { type = string }
variable "schedule" { type = string }

resource "google_pubsub_topic" "rotate_topic" {
  name    = "rotate-uptime-token-topic"
  project = var.project
}

resource "google_storage_bucket" "function_source" {
  name     = "${var.project}-rotate-fn-src"
  location = var.region
  project  = var.project
}

# NOTE: This is a skeleton. Deploy the Cloud Function from the source archive or
# use Cloud Build to upload sources. This module defines the Pub/Sub topic and
# the Cloud Scheduler job configuration.

resource "google_cloud_scheduler_job" "rotate_job" {
  name     = "rotate-uptime-token-job"
  project  = var.project
  region   = var.region
  schedule = var.schedule

  pubsub_target {
    topic_name = google_pubsub_topic.rotate_topic.id
    data       = base64encode(jsonencode({ action = "rotate" }))
  }
}

output "topic" {
  value = google_pubsub_topic.rotate_topic.name
}
