variable "namespace" {
  type    = string
  default = "postgres"
}

variable "release_name" {
  type    = string
  default = "postgresql"
}

variable "chart_version" {
  type    = string
  default = "12.9.6"
}

variable "persistence_size" {
  type    = string
  default = "10Gi"
}

variable "storage_class" {
  type    = string
  default = ""
}

variable "database_name" {
  type    = string
  default = "registry"
}

variable "database_user" {
  type    = string
  default = "harbor"
}

variable "harbor_db_secret_name" {
  type    = string
  default = "harbor-db-password"
}
