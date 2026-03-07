// Image preload automation deployment
// Deploys the airgap-control-plane Helm chart for container image preloading


resource "helm_release" "airgap_control_plane" {
  name      = var.helm_release_name
  chart     = var.helm_repository == "" ? "${path.module}/../../../deploy/charts/airgap-control-plane" : var.helm_chart_name
  version   = var.helm_repository != "" ? var.helm_chart_version : null
  namespace = kubernetes_namespace_v1.airgap_control_plane.metadata[0].name

  # Only set repository if provided (empty repository indicates local chart path)
  repository = var.helm_repository != "" ? var.helm_repository : null

  values = [
    templatefile("${path.module}/helm-values.tpl", {
      image_loader_image         = var.image_loader_image
      image_loader_pvc           = var.image_loader_pvc
      image_pull_secrets_enabled = var.image_pull_secrets_enabled
      collector_enabled          = tostring(var.collector_enabled)
      collector_image            = var.collector_image
      collector_endpoint         = var.collector_endpoint
      registry_mirror_enabled    = tostring(var.registry_mirror_enabled)
      registry_mirror_url        = var.registry_mirror_url
    })
  ]

  # Ensure namespace is created first
  depends_on = [kubernetes_namespace_v1.airgap_control_plane]
}

// Offline registry mirror configuration using Kubernetes configmaps
// This stores the registry mirror settings for container runtimes
resource "kubernetes_config_map_v1" "registry_mirrors" {
  count = var.registry_mirror_enabled ? 1 : 0

  metadata {
    name      = "registry-mirrors-config"
    namespace = kubernetes_namespace_v1.airgap_control_plane.metadata[0].name
  }

  data = {
    "registry-mirrors.json" = jsonencode({
      registries = [
        {
          name   = var.registry_mirror_url
          mirror = var.registry_mirror_url
        }
      ]
      credentials = {
        (var.registry_mirror_url) = {
          auth_enabled = var.registry_auth_enabled
          username     = var.registry_username != "" ? var.registry_username : null
          # Password should be stored in a secret, not a configmap
        }
      }
    })
  }

  depends_on = [kubernetes_namespace_v1.airgap_control_plane]
}

// Registry credentials secret for private registries
resource "kubernetes_secret_v1" "registry_credentials" {
  count = var.registry_auth_enabled ? 1 : 0

  metadata {
    name      = "registry-credentials"
    namespace = kubernetes_namespace_v1.airgap_control_plane.metadata[0].name
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = base64encode(var.registry_username)
    password = base64encode(var.registry_password)
  }

  depends_on = [kubernetes_namespace_v1.airgap_control_plane]
}

// PVC for image tarballs storage (if not using external storage)
resource "kubernetes_persistent_volume_claim_v1" "image_storage" {
  count = var.create_image_storage_pvc ? 1 : 0

  metadata {
    name      = var.image_loader_pvc
    namespace = kubernetes_namespace_v1.airgap_control_plane.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name

    resources {
      requests = {
        storage = var.image_storage_size
      }
    }
  }

  depends_on = [kubernetes_namespace_v1.airgap_control_plane]
}
