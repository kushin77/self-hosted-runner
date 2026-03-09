terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0"
    }
  }
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_version
  namespace  = var.namespace
  create_namespace = true
}

resource "helm_release" "prometheus_adapter" {
  count      = var.install_prometheus_adapter ? 1 : 0
  name       = "prometheus-adapter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-adapter"
  version    = var.prometheus_adapter_version
  namespace  = var.namespace
  depends_on = [helm_release.keda]
  values = [
    <<EOF
rules:
  - seriesQuery: 'kubernetes_cpu_usage_seconds_total'
    resources:
      overrides:
        kubernetes_pod_name: {resource: "pod"}
EOF
  ]
}
