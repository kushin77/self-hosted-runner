terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# ============================================================================
# Data source: AWS caller identity for ARN construction
# ============================================================================
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# ============================================================================
# EKS Cluster IAM Role
# ============================================================================
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster_role.name
}

# ============================================================================
# Security Group for Cluster Control Plane
# ============================================================================
resource "aws_security_group" "cluster_security_group" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS cluster control plane"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

# ============================================================================
# EKS Cluster
# ============================================================================
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = concat(var.subnet_ids, var.private_subnet_ids)
    security_groups         = [aws_security_group.cluster_security_group.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller
  ]

  tags = var.tags
}

# ============================================================================
# Node Group IAM Role
# ============================================================================
resource "aws_iam_role" "node_group_role" {
  name = "${var.cluster_name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_group_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_cni_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_ecr_policy" {
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# SSM access for systems manager
resource "aws_iam_role_policy_attachment" "node_group_ssm_policy" {
  count      = var.enable_ssm_access ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group_role.name
}

# ============================================================================
# Node Group Security Group
# ============================================================================
resource "aws_security_group" "node_group_sg" {
  name_prefix = "${var.cluster_name}-node-"
  vpc_id      = var.vpc_id
  description = "Security group for EKS worker nodes"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-sg"
  })
}

# ============================================================================
# EKS Node Group
# ============================================================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  instance_types = var.instance_types
  disk_size      = var.disk_size

  vpc_config {
    security_groups = [aws_security_group.node_group_sg.id]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-node-group"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_group_policy,
    aws_iam_role_policy_attachment.node_group_cni_policy,
    aws_iam_role_policy_attachment.node_group_ecr_policy
  ]
}

# ============================================================================
# OIDC Provider for IRSA (IAM Roles for Service Accounts)
# ============================================================================
data "tls_certificate" "cluster_certificate" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_certificate.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}

# ============================================================================
# Kubernetes Provider Configuration
# ============================================================================
provider "kubernetes" {
  host                   = aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_auth.cluster.token
}

data "aws_eks_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_auth.cluster.token
  }
}

# ============================================================================
# Service Account for Secrets Store CSI Driver
# ============================================================================
resource "kubernetes_namespace" "secrets_store" {
  metadata {
    name = "kube-system"
  }

  depends_on = [aws_eks_node_group.main]
}

resource "aws_iam_role" "secrets_store_csi_driver_role" {
  name = "${var.cluster_name}-secrets-store-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster_oidc.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:secrets-store-csi-driver"
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "kubernetes_service_account" "secrets_store_csi_driver" {
  metadata {
    name      = "secrets-store-csi-driver"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.secrets_store_csi_driver_role.arn
    }
  }

  depends_on = [kubernetes_namespace.secrets_store]
}

# ============================================================================
# Secrets Store CSI Driver Installation via Helm
# ============================================================================
resource "helm_release" "secrets_store_csi_driver" {
  count            = var.enable_secrets_store_csi ? 1 : 0
  name             = "secrets-store-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart            = "secrets-store-csi-driver"
  namespace        = "kube-system"
  version          = var.csi_driver_version
  create_namespace = false

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.secrets_store_csi_driver.metadata[0].name
  }

  set {
    name  = "linux.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.secrets_store_csi_driver_role.arn
  }

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  depends_on = [kubernetes_service_account.secrets_store_csi_driver]
}

# ============================================================================
# Service Account for Vault Provider
# ============================================================================
resource "aws_iam_role" "vault_provider_role" {
  name = "${var.cluster_name}-vault-provider-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster_oidc.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:vault-provider"
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "kubernetes_service_account" "vault_provider" {
  metadata {
    name      = "vault-provider"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.vault_provider_role.arn
    }
  }

  depends_on = [kubernetes_namespace.secrets_store]
}

# ============================================================================
# Vault Secrets Provider Installation via Helm
# ============================================================================
resource "helm_release" "vault_secrets_provider" {
  count            = var.enable_secrets_store_csi && var.vault_address != "" ? 1 : 0
  name             = "vault-secrets-provider"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.vault_provider.metadata[0].name
  }

  set {
    name  = "vault.address"
    value = var.vault_address
  }

  set {
    name  = "vault.namespace"
    value = var.vault_namespace
  }

  depends_on = [
    kubernetes_service_account.vault_provider,
    helm_release.secrets_store_csi_driver
  ]
}

# ============================================================================
# Service Account for GSM Provider
# ============================================================================
resource "aws_iam_role" "gsm_provider_role" {
  name = "${var.cluster_name}-gsm-provider-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.cluster_oidc.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:gsm-provider"
            "${replace(aws_iam_openid_connect_provider.cluster_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "kubernetes_service_account" "gsm_provider" {
  metadata {
    name      = "gsm-provider"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.gsm_provider_role.arn
    }
  }

  depends_on = [kubernetes_namespace.secrets_store]
}

# ============================================================================
# Create namespace for application workloads
# ============================================================================
resource "kubernetes_namespace" "workloads" {
  metadata {
    name = "workloads"
    labels = {
      "app.kubernetes.io/name"       = "workloads"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# ============================================================================
# Create namespace for CronJob runner
# ============================================================================
resource "kubernetes_namespace" "cron_jobs" {
  metadata {
    name = "cron-jobs"
    labels = {
      "app.kubernetes.io/name"       = "cron-jobs"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_node_group.main]
}
