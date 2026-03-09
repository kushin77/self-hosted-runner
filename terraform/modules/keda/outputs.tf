output "keda_release_name" {
  value = helm_release.keda.name
}

output "prometheus_adapter_release_name" {
  value = helm_release.prometheus_adapter.name
}
