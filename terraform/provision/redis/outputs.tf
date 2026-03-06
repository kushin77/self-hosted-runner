output "namespace" {
  value = kubernetes_namespace.redis.metadata[0].name
}

output "release_name" {
  value = helm_release.redis.name
}

output "harbor_redis_secret_name" {
  value = kubernetes_secret.harbor_redis_password.metadata[0].name
}
