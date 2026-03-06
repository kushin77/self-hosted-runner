output "namespace" {
  value = kubernetes_namespace.postgres.metadata[0].name
}

output "release_name" {
  value = helm_release.postgresql.name
}

output "harbor_db_secret_name" {
  value = kubernetes_secret.harbor_db_password.metadata[0].name
}
