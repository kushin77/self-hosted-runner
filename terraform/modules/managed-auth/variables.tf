variable "namespace" {
  description = "Kubernetes namespace for managed-auth deployment"
  type        = string
  default     = "managed-auth"
}

variable "replica_count" {
  description = "Number of pod replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "Replica count must be between 1 and 10."
  }
}

variable "image_repository" {
  description = "Docker image repository"
  type        = string
  default     = "gcr.io/runnercloud/managed-auth"
}

variable "image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "port" {
  description = "Service port"
  type        = number
  default     = 8080
}

variable "vault_addr" {
  description = "HashiCorp Vault address"
  type        = string

  validation {
    condition     = can(regex("^https?://", var.vault_addr))
    error_message = "Vault address must be a valid URL."
  }
}

variable "vault_namespace" {
  description = "Vault namespace (for enterprise)"
  type        = string
  default     = ""
}

variable "vault_auth_method" {
  description = "Vault authentication method (kubernetes, jwt, approle)"
  type        = string
  default     = "kubernetes"

  validation {
    condition     = contains(["kubernetes", "jwt", "approle"], var.vault_auth_method)
    error_message = "Vault auth method must be kubernetes, jwt, or approle."
  }
}

variable "database_host" {
  description = "PostgreSQL database host"
  type        = string
}

variable "database_port" {
  description = "PostgreSQL database port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "managed_auth"
}

variable "database_user" {
  description = "PostgreSQL database user"
  type        = string
  default     = "managed_auth"
  sensitive   = true
}

variable "database_password" {
  description = "PostgreSQL database password"
  type        = string
  sensitive   = true
}

variable "token_ttl_max" {
  description = "Maximum token TTL in seconds"
  type        = number
  default     = 28800  # 8 hours

  validation {
    condition     = var.token_ttl_max >= 60 && var.token_ttl_max <= 86400
    error_message = "Token TTL must be between 60 and 86400 seconds."
  }
}

variable "heartbeat_interval" {
  description = "Heartbeat interval in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.heartbeat_interval >= 10 && var.heartbeat_interval <= 300
    error_message = "Heartbeat interval must be between 10 and 300 seconds."
  }
}

variable "heartbeat_timeout" {
  description = "Heartbeat timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.heartbeat_timeout > var.heartbeat_interval
    error_message = "Heartbeat timeout must be greater than interval."
  }
}

variable "enable_mtls" {
  description = "Enable mTLS for client connections"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_tracing" {
  description = "Enable OpenTelemetry tracing"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level (debug, info, warn, error)"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warn", "error"], var.log_level)
    error_message = "Log level must be debug, info, warn, or error."
  }
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Component = "managed-auth"
    ManagedBy = "Terraform"
  }
}
