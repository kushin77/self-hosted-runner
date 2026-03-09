variable "project" {
  description = "GCP project ID for resource deployment"
  type        = string
}

variable "tenant_id" {
  description = "Identifier for the specific tenant or engineering group"
  type        = string
}

variable "runner_group_name" {
  description = "Name for the GitHub Runner group (must exist or be created by ID)"
  type        = string
}

variable "vpc_id" {
  description = "Target VPC for isolated runner deployment"
  type        = string
}

variable "subnet_ids" {
  description = "Target subnets within the isolated VPC"
  type        = list(string)
}

variable "labels" {
  description = "Additional labels for runner isolation (e.g. tier:high-sec, group:payments)"
  type        = map(string)
  default     = {}
}

variable "network_tags" {
  description = "Extra network tags to apply to the instance template for firewall targeting"
  type        = list(string)
  default     = []
}

variable "allowed_ingress_cidrs" {
  description = "Ingress CIDRs that are explicitly allowed for the tenant"
  type        = list(string)
  default     = []
}

variable "allowed_ingress_ports" {
  description = "Ports allowed by the ingress firewall (e.g. 443 for webhook callbacks)"
  type        = list(number)
  default     = [443]
}

variable "allowed_egress_cidrs" {
  description = "Additional egress destinations beyond the mandatory metadata range"
  type        = list(string)
  default     = []
}

variable "required_egress_cidrs" {
  description = "Destinations that must stay reachable for bootstrapping (metadata, internal services)"
  type        = list(string)
  default     = ["169.254.169.254/32"]
}

variable "allowed_egress_ports" {
  description = "Ports permitted to reach allowed egress CIDRs"
  type        = list(number)
  default     = [443]
}

variable "machine_type" {
  description = "Machine type for tenant runners"
  type        = string
  default     = "e2-standard-4"
}

variable "region" {
  description = "Region for the runner template"
  type        = string
  default     = "us-central1"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size for the runner template (in GB)"
  type        = number
  default     = 50
}

variable "boot_disk_type" {
  description = "Boot disk type for improved performance"
  type        = string
  default     = "pd-balanced"
}

variable "service_account_email" {
  description = "Optional service account used by the runner instances"
  type        = string
  default     = ""
}

variable "service_account_scopes" {
  description = "Scopes applied to the runner service account"
  type        = list(string)
  default     = ["https://www.googleapis.com/auth/cloud-platform"]
}

variable "custom_startup_script" {
  description = "Supply a custom startup script; defaults to the bundled bootstrapper"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "Optional public key data that can be injected into the template metadata for bootstrap verification"
  type        = string
  default     = ""
}

variable "extra_metadata" {
  description = "Additional metadata entries which are merged into the template"
  type        = map(string)
  default     = {}
}

variable "inject_vault_agent_metadata" {
  description = "When true, embed Vault Agent config, template, and systemd unit into instance metadata so images don't need to be rebuilt."
  type        = bool
  default     = false
}

