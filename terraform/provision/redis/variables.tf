variable "namespace" {
  type    = string
  default = "redis"
}

variable "release_name" {
  type    = string
  default = "redis"
}

variable "chart_version" {
  type    = string
  default = "17.8.11"
}

variable "persistence_size" {
  type    = string
  default = "5Gi"
}

variable "storage_class" {
  type    = string
  default = ""
}

variable "harbor_redis_secret_name" {
  type    = string
  default = "harbor-redis-password"
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
