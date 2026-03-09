module "runner_workload_identity" {
  source             = "../../modules/workload-identity"
  project            = "p4-platform"
  service_account_id = "runner-staging-a"
  display_name       = "Runner service account (staging)"
  roles              = [
    "roles/secretmanager.secretAccessor",
    "roles/storage.objectViewer"
  ]
}

output "runner_sa_email" {
  value = module.runner_workload_identity.service_account_email
}
