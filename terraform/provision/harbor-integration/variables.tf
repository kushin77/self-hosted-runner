variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "harbor_namespace" {
  type    = string
  default = "harbor"
}

variable "postgres_module_path" {
  type    = string
  default = "../postgres"
}

variable "redis_module_path" {
  type    = string
  default = "../redis"
}

variable "harbor_db_secret_name" {
  type    = string
  default = "harbor-db-password"
}

variable "harbor_redis_secret_name" {
  type    = string
  default = "harbor-redis-password"
}
