provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

resource "random_password" "redis_password" {
  length           = 20
  override_char_set = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"
}

resource "kubernetes_namespace" "redis" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "redis" {
  name       = var.release_name
  namespace  = kubernetes_namespace.redis.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  version    = var.chart_version

  values = [
    yamlencode({
      global = { "imageRegistry" = "" }
      architecture = "standalone"
      persistence = {
        size = var.persistence_size
        storageClass = var.storage_class
      }
      auth = {
        enabled = true
        password = random_password.redis_password.result
      }
    })
  ]
}

resource "kubernetes_secret" "harbor_redis_password" {
  metadata {
    name      = var.harbor_redis_secret_name
    namespace = var.namespace
  }

  data = {
    password = base64encode(random_password.redis_password.result)
  }
  type = "Opaque"
}

output "redis_password" {
  value     = random_password.redis_password.result
  sensitive = true
}
