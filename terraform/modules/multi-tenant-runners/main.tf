locals {
  runner_labels = merge(var.labels, {
    tenant = var.tenant_id
    phase  = "p4"
  })

  runner_label_string = join(",", [for key, value in local.runner_labels : "${key}:${value}"])

  runner_tags = distinct(concat(var.network_tags, ["runner", "tenant-${var.tenant_id}", "phase-p4"]))

  metadata_script = var.custom_startup_script != "" ? var.custom_startup_script : <<-EOT
    #!/bin/bash
    set -euo pipefail

    # Fetch the repository-provided startup wrapper which handles OIDC/Vault bootstrap,
    # registry login, token renewal helper, and eventual runner registration.
    BOOTSTRAP_URL="https://raw.githubusercontent.com/kushin77/self-hosted-runner/main/scripts/identity/runner-startup.sh"
    BOOTSTRAP_PATH="/tmp/runner-startup.sh"

    if ! command -v curl >/dev/null 2>&1; then
      echo "curl required to fetch bootstrapper; please install curl or provide a custom_startup_script"
      exit 1
    fi

    echo "Fetching runner startup wrapper from ${BOOTSTRAP_URL}"
    curl -fsSL "${BOOTSTRAP_URL}" -o "${BOOTSTRAP_PATH}"
    chmod +x "${BOOTSTRAP_PATH}"

    # Execute the startup wrapper; it will attempt OIDC->Vault login and then register the runner
    exec "${BOOTSTRAP_PATH}"
  EOT

  metadata_base = {
    "startup-script" = chomp(local.metadata_script)
  }

  metadata = merge(
    local.metadata_base,
    var.ssh_public_key != "" ? { "ssh-keys" = "runner-deployer:${var.ssh_public_key}" } : {},
    var.extra_metadata
  )

  effective_allowed_egress_cidrs = distinct(compact(concat(var.required_egress_cidrs, var.allowed_egress_cidrs)))

  ingress_ports = length(var.allowed_ingress_ports) > 0 ? [for port in var.allowed_ingress_ports : tostring(port)] : ["443"]
  egress_ports  = length(var.allowed_egress_ports) > 0 ? [for port in var.allowed_egress_ports : tostring(port)] : ["443"]
}

resource "google_compute_instance_template" "runner_template" {
  name_prefix  = "runner-${var.tenant_id}-"
  machine_type = var.machine_type
  region       = var.region
  tags         = local.runner_tags
  labels       = local.runner_labels
  metadata     = local.metadata

  disk {
    auto_delete = true
    boot        = true
    initialize_params {
      disk_size_gb = var.boot_disk_size_gb
      disk_type    = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[0]
  }

  dynamic "service_account" {
    for_each = var.service_account_email != "" ? [1] : []
    content {
      email  = var.service_account_email
      scopes = var.service_account_scopes
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_firewall" "runner_ingress_allow" {
  count       = length(var.allowed_ingress_cidrs) > 0 ? 1 : 0
  name        = "runner-${var.tenant_id}-allow-ingress"
  network     = var.vpc_id
  direction   = "INGRESS"
  priority    = 100
  target_tags = local.runner_tags

  allow {
    protocol = "tcp"
    ports    = local.ingress_ports
  }

  source_ranges = var.allowed_ingress_cidrs
}

resource "google_compute_firewall" "runner_ingress_deny" {
  name        = "runner-${var.tenant_id}-deny-ingress"
  network     = var.vpc_id
  direction   = "INGRESS"
  priority    = 1000
  target_tags = local.runner_tags

  deny {
    protocol = "all"
  }
}

resource "google_compute_firewall" "runner_egress_allow" {
  count              = length(local.effective_allowed_egress_cidrs) > 0 ? 1 : 0
  name               = "runner-${var.tenant_id}-allow-egress"
  network            = var.vpc_id
  direction          = "EGRESS"
  priority           = 100
  target_tags        = local.runner_tags
  destination_ranges = local.effective_allowed_egress_cidrs

  allow {
    protocol = "tcp"
    ports    = local.egress_ports
  }
}

resource "google_compute_firewall" "runner_egress_deny" {
  name        = "runner-${var.tenant_id}-deny-egress"
  network     = var.vpc_id
  direction   = "EGRESS"
  priority    = 1000
  target_tags = local.runner_tags

  deny {
    protocol = "all"
  }
}