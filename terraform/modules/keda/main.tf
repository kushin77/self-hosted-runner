terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.5.0"
    }
  }
}

provider "helm" {}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_version
  namespace  = var.namespace
  create_namespace = true
}

resource "helm_release" "prometheus_adapter" {
  name       = "prometheus-adapter"
  repository = "https://kubernetes-sigs.github.io/prometheus-adapter"
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
