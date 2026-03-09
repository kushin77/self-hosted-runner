output "keda_release_name" {
  value = helm_release.keda.name
}

output "prometheus_adapter_release_name" {
  value = length(helm_release.prometheus_adapter) > 0 ? helm_release.prometheus_adapter[0].name : ""
}
