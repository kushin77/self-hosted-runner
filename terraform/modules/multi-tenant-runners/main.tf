# Resource: Isolated Runner Deployment (GCP Instance Group / AWS ASG Template)
# This module implements multi-tenant isolation via VPC-scoping and Github labels.

resource "google_compute_instance_template" "runner_template" {
  name_prefix  = "runner-${var.tenant_id}-"
  machine_type = "e2-standard-4"
  region       = "us-central1"

  tags = ["runner", "tenant-${var.tenant_id}"]

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[0]
  }

  metadata = {
    ssh-keys = "runner-deployer:${file("~/.ssh/id_rsa.pub")}"
    # Use startup script to register runner with specific group/labels
    startup-script = <<-EOT
      #!/bin/bash
      RUNNER_ALLOW_RUNASROOT=1 ./config.sh --url https://github.com/kushin77/self-hosted-runner --token $REG_TOKEN --runnergroup ${var.runner_group_name} --labels ${join(",", var.labels)}
    EOT
  }

  labels = merge(var.labels, {
    tenant = var.tenant_id
    phase  = "p4"
  })

  lifecycle {
    create_before_destroy = true
  }
}
