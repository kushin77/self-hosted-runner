# Air-Gap Control Plane Terraform Module

This Terraform module provisions a secure, air-gapped Kubernetes control plane for self-hosted GitHub Actions runners. It includes image preloading automation, offline registry mirroring support, and network policy enforcement.

## Features

- **Namespace & Network Policies**: Creates isolated Kubernetes namespace with restricted egress policies
- **Image Preload Automation**: Deploys Helm chart for automated container image loading from PVCs
- **Registry Mirroring**: Configures offline registry mirror (e.g., Harbor) for image pulls in air-gapped environments
- **Credential Management**: Manages registry authentication credentials securely
- **OTEL Collector**: Optional OpenTelemetry collector for observability in disconnected networks

## Prerequisites

- Terraform >= 1.0
- Kubernetes >= 1.23
- Helm >= 3.10
- kubectl configured to access target cluster
- (Optional) Harbor or similar private registry pre-deployed

## Module Structure

```
├── main.tf                    # Main namespace and placeholder resources
├── namespace_networkpolicy.tf # Network policy configuration
├── image-preload.tf          # Image preload, registry mirror, and PVC resources
├── outputs.tf                # Output values for downstream consumption
├── variables.tf              # Input variables with descriptions
├── providers.tf              # Provider configuration (Kubernetes, Helm)
├── helm-values.tpl           # Helm chart values template
└── README.md                 # This file
```

## Usage

### Basic Example

```hcl
module "airgap_control_plane" {
  source = "./terraform/modules/airgap-control-plane"

  namespace_name    = "runnercloud"
  cluster_name      = "my-k8s-cluster"
  
  # Network policies
  allowed_registry_cidr   = "10.0.0.0/24"  # Private registry CIDR
  allowed_collector_cidr  = "10.0.1.0/24"  # Observability collector CIDR

  # Image preload
  image_storage_size     = "100Gi"
  create_image_storage_pvc = true

  # Registry mirror
  registry_mirror_enabled = true
  registry_mirror_url     = "harbor.internal.example.com"
  registry_auth_enabled   = true
  registry_username       = "admin"
  registry_password       = var.harbor_password

  # OTEL collector
  collector_enabled       = true
  collector_endpoint      = "10.0.1.100:4317"
}
```

### Helm Release Configuration

```hcl
module "airgap_control_plane" {
  source = "./terraform/modules/airgap-control-plane"

  namespace_name = "runnercloud"
  cluster_name   = "my-k8s-cluster"

  # Use custom Helm repository
  helm_repository    = "https://example.com/helm-repo"
  helm_chart_version = "2.0.0"
  helm_release_name  = "runners-cp"

  # Image loader configuration
  image_loader_image = "custom-registry.com/image-loader:v1.0"
  image_loader_pvc   = "custom-image-pvc"

  # ... additional configuration
}
```

## Variables

### Networking

- `namespace_name` (string): Kubernetes namespace name. Default: `"airgap-control-plane"`
- `namespace_labels` (map): Labels for the namespace. Default: `{}`
- `cluster_name` (string, **required**): Name of the target Kubernetes cluster
- `allowed_registry_cidr` (string): CIDR for registry egress. Default: `"0.0.0.0/0"` (restrict in production)
- `allowed_collector_cidr` (string): CIDR for collector egress. Default: `"0.0.0.0/0"` (restrict in production)

### Helm Configuration

- `helm_release_name` (string): Helm release name. Default: `"airgap-control-plane"`
- `helm_repository` (string): Helm repository URL. Default: `""` (local path)
- `helm_chart_name` (string): Helm chart name. Default: `"airgap-control-plane"`
- `helm_chart_version` (string): Helm chart version. Default: `"1.0.0"`

### Image Preload

- `image_loader_image` (string): Image loader container image. Default: `"alpine:latest"`
- `image_loader_pvc` (string): PVC name for image tarballs. Default: `"image-storage-pvc"`
- `image_pull_secrets_enabled` (bool): Enable image pull secrets. Default: `false`
- `create_image_storage_pvc` (bool): Create image storage PVC. Default: `true`
- `image_storage_size` (string): PVC size. Default: `"50Gi"`
- `storage_class_name` (string): Storage class for PVC. Default: `"standard"`

### Collector

- `collector_enabled` (bool): Enable OTEL collector. Default: `true`
- `collector_image` (string): OTEL collector image. Default: `"otel/opentelemetry-collector-k8s:latest"`
- `collector_endpoint` (string): OTEL collector endpoint. Default: `""`

### Registry Mirror

- `registry_mirror_enabled` (bool): Enable registry mirror. Default: `true`
- `registry_mirror_url` (string): Registry mirror URL (e.g., `harbor.example.com`). Default: `""`
- `registry_auth_enabled` (bool): Enable registry auth. Default: `false`
- `registry_username` (string, sensitive): Registry username. Default: `""`
- `registry_password` (string, sensitive): Registry password. Default: `""`

## Outputs

- `namespace_name`: Name of the created namespace
- `namespace_id`: ID of the created namespace
- `egress_policy_name`: Name of the egress network policy
- `egress_policy_id`: ID of the egress network policy

## Network Policies

The module enforces restricted network egress:

```
- Intra-namespace traffic: ALLOWED
- Egress to registry CIDR: ALLOWED (configurable)
- Egress to collector CIDR: ALLOWED (configurable)
- All other egress: DENIED (default)
```

For production deployments, restrict `allowed_registry_cidr` and `allowed_collector_cidr` to specific, minimal IP ranges.

## Image Preloading Workflow

1. **Prepare Images**: Export container images as tarballs and place in the image storage PVC
2. **Deploy Module**: Apply Terraform configuration to provision namespace and network policies
3. **Deploy Helm Chart**: The module deploys the `airgap-control-plane` Helm chart
4. **Image Load Job Runs**: The Helm chart automatically spawns an image-load job that:
   - Detects available container runtime (ctr, docker, podman)
   - Loads tarballs from the PVC into the container runtime
   - Registers images in the offline registry

## Registry Mirror Setup

### Step 1: Deploy Private Registry (e.g., Harbor)

Before using this module, deploy a private registry:

```bash
helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor \
  --namespace harbor \
  --values harbor-values.yaml
```

### Step 2: Configure Registry Mirror in Kubernetes

This module creates a ConfigMap with registry mirror settings. Ensure node-level or kubelet-level registry mirroring is configured:

```yaml
# /etc/containerd/config.toml (for containerd)
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["https://harbor.internal.example.com/v2/docker.io"]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io".auth]
    username = "admin"
    password = "your-password"
```

### Step 3: Pre-load Images

Copy required container images into the image storage PVC:

```bash
# Export images as tarballs
docker save -o busybox.tar busybox:latest
docker save -o runner.tar ghcr.io/actions/runner:latest

# Mount PVC and copy
kubectl exec -it -n runnercloud <pod> -- /bin/sh
kubectl cp busybox.tar runnercloud/<pod>:/images/
kubectl cp runner.tar runnercloud/<pod>:/images/
```

## Testing

See [../../.github/workflows/test-airgap-module.yml](../../.github/workflows/test-airgap-module.yml) for CI/CD integration tests.

### Manual Testing

```bash
cd terraform/modules/airgap-control-plane

# Validate configuration
terraform init
terraform validate

# Plan deployment
terraform plan -var-file=test.tfvars -out=tfplan

# Apply (requires Kubernetes access)
terraform apply tfplan

# Verify namespace and policies
kubectl get ns
kubectl get networkpolicies -n airgap-control-plane

# Check Helm release
helm list -n airgap-control-plane

# Monitor image load job
kubectl get jobs -n airgap-control-plane
kubectl logs -n airgap-control-plane -f job/airgap-control-plane-image-load
```

## Troubleshooting

### Images Not Loading

- **Check Job Status**: `kubectl describe job -n airgap-control-plane airgap-control-plane-image-load`
- **Verify PVC**: `kubectl get pvc -n airgap-control-plane`
- **Check Image Tarballs**: Ensure tarballs are in PVC: `kubectl exec ... -n airgap-control-plane -- ls /images/`

### Network Policy Blocks Traffic

- Verify CIDR ranges: `kubectl get networkpolicy -n airgap-control-plane -o yaml`
- Check pod logs: `kubectl logs -n airgap-control-plane <pod-name>`
- Temporarily relax policy for debugging

### Registry Mirror Not Resolving

- Verify registry URL is reachable: `curl https://registry_mirror_url/v2/`
- Check credentials: `kubectl get secret -n airgap-control-plane registry-credentials -o yaml`
- Ensure registry DNS is available in air-gap network

## Security Considerations

1. **Network Isolation**: Always restrict `allowed_registry_cidr` and `allowed_collector_cidr` to specific, minimal ranges
2. **Secrets Management**: Use proper secret management (e.g., HashiCorp Vault) for registry credentials
3. **RBAC**: Apply least-privilege RBAC rules to namespace
4. **Image Signing**: Verify signed container images before loading
5. **Audit Logging**: Enable audit logging on network policies and secrets access

## Contributing

To contribute to this module:

1. Test changes using the test suite in `.github/workflows/test-airgap-module.yml`
2. Update module variables and outputs as needed
3. Update this README with new features or breaking changes
4. Follow HashiCorp Terraform module conventions

## References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Helm Charts Documentation](https://helm.sh/docs/)
- [Harbor Registry Documentation](https://goharbor.io/docs/)
- [Air-Gapped Deployments Best Practices](https://www.cisa.gov/sites/default/files/publications/Securing_Software_Supply_Chain_Recommendations.pdf)

## License

See LICENSE file in repository root.
