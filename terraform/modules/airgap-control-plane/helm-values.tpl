# Helm values template for airgap-control-plane deployment
# This template is rendered by Terraform with actual values

imageLoader:
  image: ${image_loader_image}
  pvc: ${image_loader_pvc}

imagePullSecrets:
  enabled: ${image_pull_secrets_enabled}

collector:
  enabled: ${collector_enabled}
  image: ${collector_image}
  endpoint: ${collector_endpoint}

registryMirror:
  enabled: ${registry_mirror_enabled}
  url: ${registry_mirror_url}

# Network policies are managed by Terraform directly
networkPolicy:
  enabled: true
  ingress: true
  egress: true
