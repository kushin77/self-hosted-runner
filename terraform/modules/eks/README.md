# EKS Module - Enterprise Kubernetes with Multi-Cloud Secrets

## Overview

This Terraform module provisions a production-ready Amazon EKS cluster with:

- **Auto-scaling node groups** with configurable instance types and sizing
- **IRSA (IAM Roles for Service Accounts)** for secure pod authentication
- **Secrets Store CSI Driver** for in-memory secret mounting
- **Multi-cloud secret providers**:
  - HashiCorp Vault
  - Google Cloud Secret Manager (GSM)
  - AWS Secrets Manager
- **Pre-configured namespaces** for workloads and CronJob execution
- **CloudWatch logging** for API server, audit, and controller logs
- **VPC integration** with security groups and network policies

## Architecture

```
┌─────────────────────────────────────────┐
│         EKS Cluster                     │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐   │
│  │ kube-system Namespace           │   │
│  ├─────────────────────────────────┤   │
│  │ • Secrets Store CSI Driver      │   │
│  │ • Vault Provider                │   │
│  │ • GSM Provider                  │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ cron-jobs Namespace             │   │
│  ├─────────────────────────────────┤   │
│  │ • Milestone Organizer CronJob   │   │
│  │ • IRSA Service Account          │   │
│  │ • Secret Volumes (CSI)          │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ workloads Namespace             │   │
│  ├─────────────────────────────────┤   │
│  │ • Application deployments       │   │
│  │ • Service accounts              │   │
│  └─────────────────────────────────┘   │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │ Node Group (3 nodes)            │   │
│  ├─────────────────────────────────┤   │
│  │ • Auto-scaling enabled          │   │
│  │ • t3.xlarge instance type       │   │
│  │ • 100GB EBS volume per node     │   │
│  │ • SSM access enabled            │   │
│  └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
         │           │           │
         ▼           ▼           ▼
    ┌────────┐  ┌────────┐  ┌─────────┐
    │ Vault  │  │  GSM   │  │AWS Sec. │
    │        │  │Manager │  │Manager  │
    └────────┘  └────────┘  └─────────┘
```

## Module Usage

### Basic Example

```hcl
module "eks" {
  source = "./terraform/modules/eks"

  cluster_name            = "milestone-organizer-eks"
  cluster_version         = "1.29"
  region                  = "us-east-1"
  vpc_id                  = "vpc-xxxxx"
  subnet_ids              = ["subnet-xxxxx", "subnet-yyyyy"]
  private_subnet_ids      = ["subnet-private-1", "subnet-private-2", "subnet-private-3"]
  
  node_group_name         = "primary"
  desired_size            = 3
  min_size                = 1
  max_size                = 10
  instance_types          = ["t3.xlarge"]
  disk_size               = 100
  
  enable_ssm_access       = true
  enable_secrets_store_csi = true
  csi_driver_version      = "v1.3.4"
  
  vault_address           = "https://vault.example.com"
  vault_namespace         = "admin"

  tags = {
    Environment = "production"
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}
```

### CronJob with IRSA

```hcl
module "cronjob_irsa" {
  source = "./terraform/modules/eks"

  # ... EKS module configuration ...

  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn       = module.eks.oidc_provider_arn
  s3_bucket_arn           = "arn:aws:s3:::milestone-organizer-archive"
  secrets_arns = [
    "arn:aws:secretsmanager:us-east-1:123456789012:secret:milestone-organizer/*"
  ]

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Inputs

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `cluster_name` | EKS cluster name | `string` |
| `region` | AWS region | `string` |
| `vpc_id` | VPC ID for the cluster | `string` |
| `subnet_ids` | List of subnet IDs (public/control plane) | `list(string)` |
| `private_subnet_ids` | List of private subnet IDs (nodes) | `list(string)` |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `cluster_version` | Kubernetes version | `string` | `"1.29"` |
| `node_group_name` | Node group name | `string` | `"primary"` |
| `desired_size` | Desired number of nodes | `number` | `3` |
| `min_size` | Minimum nodes | `number` | `1` |
| `max_size` | Maximum nodes | `number` | `10` |
| `instance_types` | EC2 instance types | `list(string)` | `["t3.xlarge"]` |
| `disk_size` | EBS volume size (GB) | `number` | `100` |
| `enable_ssm_access` | Enable SSM on nodes | `bool` | `true` |
| `enable_secrets_store_csi` | Install CSI driver | `bool` | `true` |
| `csi_driver_version` | CSI driver version | `string` | `"v1.3.4"` |
| `vault_address` | Vault server URL | `string` | `""` |
| `vault_namespace` | Vault namespace | `string` | `""` |
| `tags` | Resource tags | `map(string)` | `{}` |

## Outputs

### Cluster Information

```hcl
cluster_id                             # Cluster ID/name
cluster_arn                           # Cluster ARN
cluster_endpoint                      # API server endpoint
cluster_version                       # Kubernetes version
cluster_certificate_authority_data    # CA certificate (base64)
cluster_oidc_issuer_url              # OIDC issuer URL for IRSA
```

### Network & Security

```hcl
cluster_security_group_id             # Control plane security group
node_security_group_id                # Node group security group
```

### Node Group Information

```hcl
node_group_id                         # Node group ID
node_group_arn                        # Node group ARN
node_group_role_arn                   # Node role ARN
node_group_role_name                  # Node role name
```

### IRSA & Provider Roles

```hcl
oidc_provider_arn                     # OIDC provider ARN
secrets_store_csi_driver_role_arn     # CSI driver role ARN
vault_provider_role_arn               # Vault provider role ARN
gsm_provider_role_arn                 # GSM provider role ARN
cronjob_role_arn                      # CronJob IRSA role ARN
```

### Namespaces

```hcl
workloads_namespace                   # Workloads namespace name
cron_jobs_namespace                   # CronJob namespace name
```

## Key Features

### 1. Enterprise-Grade Security

- **IRSA**: Each service account has its own IAM role
- **Network segmentation**: Private subnets for worker nodes
- **Security groups**: Restricted ingress/egress policies
- **Audit logging**: API server and audit logs in CloudWatch
- **No root access**: Nodes run with non-root sysctls

### 2. Multi-Cloud Secrets

The module supports three secret manager backends:

**Vault Integration:**
- Automatic IRSA role configuration
- SecretProviderClass manifest generator
- Kubernetes auth method support

**Google Cloud Secret Manager:**
- Cross-account/cross-project access
- Automatic GCP credential injection
- Secret versioning support

**AWS Secrets Manager:**
- Native AWS IAM integration
- Automatic secret rotation support
- CloudTrail audit logging

### 3. Scalability & Cost

- **Auto-scaling**: HPA and cluster autoscaler compatible
- **Cost optimization**: Spot instances support (via node group config)
- **Multi-AZ**: Spreads nodes across availability zones
- **Right-sizing**: Configurable instance types and sizes

### 4. Observability

- **CloudWatch Logs**: Enabled for API server, audit, scheduler
- **Container Insights**: Compatible with CloudWatch Container Insights
- **Prometheus**: Ready for Prometheus/Grafana monitoring
- **Distributed Tracing**: OpenTelemetry compatible

## Deployment Workflow

### 1. Planning

```bash
terraform init
terraform plan -out=eks.plan
```

### 2. Review

Verify:
- Cluster size and node configuration
- Security group rules
- IAM role policies
- Provider compatibility

### 3. Apply

```bash
terraform apply eks.plan
```

### 4. Bootstrap

Configure kubectl and deploy CSI drivers:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name milestone-organizer-eks

kubectl get nodes
```

### 5. Deploy Secrets

Apply SecretProviderClass manifests:

```bash
envsubst < terraform/modules/eks/templates/secret_provider_vault.yaml | \
  kubectl apply -f -
```

### 6. Deploy Workloads

Deploy CronJob or application manifests:

```bash
envsubst < terraform/modules/eks/templates/cronjob_manifest.yaml | \
  kubectl apply -f -
```

## Troubleshooting

### Cluster Creation Issues

```bash
# Check cluster events
aws eks describe-cluster --name cluster-name

# View CloudTrail logs
aws cloudtrail lookup-events --lookup-attributes \
  AttributeKey=ResourceType,AttributeValue=AWS::EKS::Cluster
```

### CSI Driver Pod Issues

```bash
# Check driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver -f

# Verify driver installation
kubectl get csidriver
kubectl describe csidriver secrets-store.csi.k8s.io
```

### IRSA Configuration

```bash
# Verify OIDC provider
aws iam list-open-id-connect-providers

# Check service account annotations
kubectl describe sa -n cron-jobs milestone-organizer

# Test role assumption
kubectl run -it --rm test \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- sts get-caller-identity
```

## Security Considerations

1. **Node Security Groups**: Restrict to internal communication only
2. **IRSA Policies**: Follow least-privilege principle
3. **Secrets Rotation**: Enable automatic rotation in Secrets Manager
4. **Network Policies**: Implement Calico or similar network policies
5. **Pod Security**: Use Pod Security Standards or policies
6. **RBAC**: Implement fine-grained role-based access control

## Maintenance

### Update Kubernetes Version

```hcl
cluster_version = "1.30"  # Update variable
```

```bash
terraform plan && terraform apply
```

### Scale Node Group

```hcl
desired_size = 5  # Update variable
max_size     = 15
```

### Rotate Node AMI

EKS automatically manages node AMI updates via launch template.

## Cost Optimization

- Use spot instances for non-critical workloads
- Configure auto-scaling policies
- Monitor unused resources with AWS Cost Explorer
- Enable EBS volume encryption (small overhead)

## References

- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
- [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)
