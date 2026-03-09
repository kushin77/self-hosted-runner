variable "kubeconfig_path" {
  type    = string
  default = "/etc/rancher/k3s/k3s.yaml"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "random_password" "postgres_password" {
  length           = 24
  override_char_set = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
}

resource "kubernetes_namespace" "postgres" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "postgresql" {
  name       = var.release_name
  namespace  = kubernetes_namespace.postgres.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = var.chart_version

  values = [
    yamlencode({
      global = { "imageRegistry" = "" }
      persistence = {
        size = var.persistence_size
        storageClass = var.storage_class
      }
      postgresqlDatabase = var.database_name
      postgresqlUsername = var.database_user
      postgresqlPassword = random_password.postgres_password.result
      metrics = { enabled = false }
    })
  ]
}

resource "kubernetes_secret" "harbor_db_password" {
  metadata {
    name      = var.harbor_db_secret_name
    namespace = var.namespace
  }

  data = {
    password = base64encode(random_password.postgres_password.result)
  }
  type = "Opaque"
}

output "postgres_password" {
  value     = random_password.postgres_password.result
  sensitive = true
}
terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
    random     = { source = "hashicorp/random" }
  }
}

provider "helm" {}

resource "kubernetes_namespace" "postgres" {
  metadata { name = var.namespace }
}

resource "random_password" "postgres_password" {
  length  = 20
  special = true
}

resource "helm_release" "postgres" {
  name       = var.release_name
  namespace  = kubernetes_namespace.postgres.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  version    = var.chart_version

  values = [
    yamlencode({
      global = { postgresql = { postgresqlPassword = random_password.postgres_password.result } }
      persistence = { enabled = true, size = var.persistence_size, storageClass = var.storage_class }
      postgresql = { postgresqlDatabase = var.database_name, postgresqlUsername = var.database_user, postgresqlPassword = random_password.postgres_password.result }
    })
  ]
}

resource "kubernetes_secret" "harbor_db_password" {
  metadata {
    name      = var.harbor_db_secret_name
    namespace = kubernetes_namespace.postgres.metadata[0].name
  }
  data = {
    password = random_password.postgres_password.result
  }
  type = "Opaque"
}

output "postgres_host" {
  value = helm_release.postgres.status[0].name
}
