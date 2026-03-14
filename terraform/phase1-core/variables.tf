variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "github_owner" {
  description = "GitHub owner/organization for webhooks"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "gke_cluster_name" {
  description = "GKE cluster name for deployments"
  type        = string
  default     = "nexus-prod-gke"
}

variable "gke_zone" {
  description = "GKE cluster zone"
  type        = string
  default     = "us-central1-a"
}

variable "artifact_registry_location" {
  description = "Location for Artifact Registry"
  type        = string
  default     = "us-central1"
}

variable "enable_jenkins_integration" {
  description = "Enable Jenkins webhook integration"
  type        = bool
  default     = true
}

variable "enable_bitbucket_integration" {
  description = "Enable Bitbucket webhook integration"
  type        = bool
  default     = true
}

variable "enable_gitlab_integration" {
  description = "Enable GitLab webhook integration"
  type        = bool
  default     = true
}

variable "kms_key_rotation_period" {
  description = "KMS key rotation period in seconds"
  type        = string
  default     = "7776000"  # 90 days
}

variable "docker_registry" {
  description = "Docker registry for container images"
  type        = string
  default     = "us-central1-docker.pkg.dev"
}

variable "namespace" {
  description = "Kubernetes namespace for deployments"
  type        = string
  default     = "nexus-discovery"
}

variable "log_retention_days" {
  description = "Audit log retention in days"
  type        = number
  default     = 90
}

variable "labels" {
  description = "Common labels for all resources"
  type        = map(string)
  default = {
    phase       = "phase1"
    environment = "production"
    managed-by  = "terraform"
    automation  = "nexus"
  }
}
