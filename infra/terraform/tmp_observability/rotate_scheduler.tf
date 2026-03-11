module "rotate_scheduler" {
  source = "../../modules/ops/rotate_scheduler"
  project = var.project_id
  region  = var.region
  schedule = "0 3 * * *" # daily at 03:00 UTC
}

output "rotate_topic" {
  value = module.rotate_scheduler.topic_name
}

module "monitoring_secret_rotation" {
  source = "../../modules/monitoring"
  project = var.project_id
}
