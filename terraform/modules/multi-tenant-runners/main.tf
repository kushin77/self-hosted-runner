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

    # Bootstrap sequence (default):
    # 1) Install minimal packages (curl, jq) if missing
    # 2) Deploy Vault Agent config + template + systemd unit from repo
    # 3) Start/enable vault-agent.service
    # 4) Fetch and exec the runner-startup wrapper which performs OIDC->Vault login and registers the runner

    BOOTSTRAP_BASE="https://raw.githubusercontent.com/kushin77/self-hosted-runner/main"
    VAULT_AGENT_DIR="/etc/vault-agent"
    BOOTSTRAP_DIR="/tmp"

    # Ensure basic tooling
    if ! command -v curl >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl jq || true
      fi
    fi

    mkdir -p ${VAULT_AGENT_DIR}/templates

    echo "Fetching Vault Agent configuration and template"
    curl -fsSL "${BOOTSTRAP_BASE}/scripts/identity/vault-agent/vault-agent.hcl" -o "${VAULT_AGENT_DIR}/vault-agent.hcl" || true
    curl -fsSL "${BOOTSTRAP_BASE}/scripts/identity/vault-agent/registry-creds.tpl" -o "${VAULT_AGENT_DIR}/templates/registry-creds.tpl" || true
    curl -fsSL "${BOOTSTRAP_BASE}/scripts/identity/vault-agent/vault-agent.service" -o "/etc/systemd/system/vault-agent.service" || true

    # Ensure vault binary exists (best-effort; recommend baking into image for production)
    if ! command -v vault >/dev/null 2>&1; then
      echo "Vault binary not found; please bake Vault into the image for production. Skipping vault-agent auto-start."
    else
      systemctl daemon-reload || true
      systemctl enable --now vault-agent.service || true
    fi

    # Fetch and run the runner startup wrapper (handles OIDC->Vault bootstrap and runner registration)
    RUNNER_STARTUP_URL="${BOOTSTRAP_BASE}/scripts/identity/runner-startup.sh"
    RUNNER_STARTUP_PATH="${BOOTSTRAP_DIR}/runner-startup.sh"
    echo "Fetching runner startup wrapper from ${RUNNER_STARTUP_URL}"
    curl -fsSL "${RUNNER_STARTUP_URL}" -o "${RUNNER_STARTUP_PATH}" || true
    chmod +x "${RUNNER_STARTUP_PATH}"

    exec "${RUNNER_STARTUP_PATH}"
  EOT

  metadata_base = {
    "startup-script" = chomp(local.metadata_script)
  }
  metadata_pre = merge(
    local.metadata_base,
    var.ssh_public_key != "" ? { "ssh-keys" = "runner-deployer:${var.ssh_public_key}" } : {},
    var.extra_metadata
  )

  # Optionally inject Vault Agent artifacts into instance metadata so images
  # need not bundle them. This allows the startup script to write files from
  # metadata on first boot and enable Vault Agent.
  metadata = var.inject_vault_agent_metadata ? merge(local.metadata_pre, {
    "vault-agent.hcl"        = file("${path.root}/scripts/identity/vault-agent/vault-agent.hcl")
    "vault-agent.service"    = file("${path.root}/scripts/identity/vault-agent/vault-agent.service")
    "registry-creds.tpl"     = file("${path.root}/scripts/identity/vault-agent/registry-creds.tpl")
  }) : local.metadata_pre

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