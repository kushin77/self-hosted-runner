terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

module "staging_tenant_a" {
  source = "../../modules/multi-tenant-runners"

  project           = "p4-platform"
  tenant_id         = "staging-a"
  runner_group_name = "staging-tenant-a"
  vpc_id            = "projects/p4-platform/global/networks/p4-isolated"
  subnet_ids        = ["regions/us-central1/subnetworks/p4-isolated-eu"]

  labels = {
    environment = "staging"
    owner       = "platform-security"
  }

  network_tags          = ["p4-isolated"]
  allowed_ingress_cidrs = ["10.30.0.0/16"]
  allowed_ingress_ports = [443]
  allowed_egress_cidrs  = ["10.30.0.0/16", "199.232.0.0/16"]
  allowed_egress_ports  = [443, 80]
  required_egress_cidrs = ["169.254.169.254/32", "10.0.0.0/8"]

  service_account_email  = "runner-staging-a@p4-platform.iam.gserviceaccount.com"
  service_account_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

  inject_vault_agent_metadata = true

  custom_startup_script = <<-EOT
    #!/bin/bash
    REG_TOKEN="$${REG_TOKEN:-<replace-me>}"
    RUNNER_ALLOW_RUNASROOT=1 ./config.sh --url https://github.com/kushin77/self-hosted-runner --token "$REG_TOKEN" --runnergroup staging-tenant-a --labels environment:staging,owner:platform-security
  EOT

  extra_metadata = {
    "bootstrap-stage" = "phase-p4"
    "tenant"          = "staging-a"
  }
}