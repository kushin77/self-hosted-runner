module "postgres" {
  source = var.postgres_module_path

  # propagate kubeconfig path into module
  kubeconfig_path = var.kubeconfig_path
}

module "redis" {
  source = var.redis_module_path

  kubeconfig_path = var.kubeconfig_path
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

resource "kubernetes_secret" "harbor_db_password" {
  metadata {
    name      = var.harbor_db_secret_name
    namespace = var.harbor_namespace
  }

  data = {
    password = base64encode(module.postgres.postgres_password)
  }

  type = "Opaque"
}

resource "kubernetes_secret" "harbor_redis_password" {
  metadata {
    name      = var.harbor_redis_secret_name
    namespace = var.harbor_namespace
  }

  data = {
    password = base64encode(module.redis.redis_password)
  }

  type = "Opaque"
}

output "harbor_db_secret_name" {
  value = kubernetes_secret.harbor_db_password.metadata[0].name
}

output "harbor_redis_secret_name" {
  value = kubernetes_secret.harbor_redis_password.metadata[0].name
}
