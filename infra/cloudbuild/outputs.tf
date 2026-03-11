output "trigger_name" {
  value = google_cloudbuild_trigger.gov_scan.name
}

output "trigger_id" {
  value = google_cloudbuild_trigger.gov_scan.id
}

output "scheduler_job" {
  value = google_cloud_scheduler_job.gov_scan_daily.name
}
