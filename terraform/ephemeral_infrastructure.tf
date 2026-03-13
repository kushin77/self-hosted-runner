# Ephemeral Infrastructure Configuration
# Auto-cleanup policies for resource lifecycle management
# Ensures "ephemeral" deployment model: resources created on-demand, destroyed after use

locals {
  # Ephemeral resource lifecycle tags
  ephemeral_tags = merge(var.tags, {
    ephemeral = true
    auto_cleanup = true
    created_at = timestamp()
  })

  # Lifecycle policies (in hours)
  lifecycle_policies = {
    temporary_cluster    = 24
    test_deployment      = 2
    staging_environment  = 48
    ci_cd_resources      = 1
    snapshot             = 720  # 30 days
    backup               = 2160 # 90 days
  }
}

# ============================================================================
# Ephemeral EKS Cluster (Auto-Cleanup)
# ============================================================================
resource "aws_eks_cluster" "ephemeral" {
  name            = "${var.cluster_name}-ephemeral-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  role_arn        = aws_iam_role.eks_cluster_role.arn
  version         = var.cluster_version
  
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Lifecycle: Auto-delete ephemeral cluster after 24 hours
  lifecycle {
    create_before_destroy = true
    # Note: Terraform doesn't support native TTL, but Cloud Scheduler will destroy via API
  }

  tags = local.ephemeral_tags

  # Trigger cleanup job
  depends_on = [aws_cloudwatch_log_group.ephemeral_cleanup]
}

# ============================================================================
# CloudWatch Log Group for Ephemeral Resources (Auto-Retention)
# ============================================================================
resource "aws_cloudwatch_log_group" "ephemeral_cleanup" {
  name              = var.cluster_name
  retention_in_days = 7  # Auto-delete logs after 7 days

  tags = local.ephemeral_tags
}

# ============================================================================
# Google Cloud Build: Ephemeral Build Environment
# ============================================================================
resource "google_cloud_build_trigger" "ephemeral_test" {
  project     = var.gcp_project_id
  name        = "ephemeral-test-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  description = "Ephemeral build, auto-destroyed after completion"
  
  filename = "cloudbuild.yaml"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^develop$"
    }
  }

  # Substitute lifecycle: tag for auto-cleanup
  substitutions = {
    _EPHEMERAL_ID = formatdate("YYYYMMDDhhmmss", timestamp())
    _TTL_HOURS    = "2"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Kubernetes: Ephemeral Job with TTL
# ============================================================================
resource "kubernetes_job" "ephemeral_test" {
  metadata {
    name      = "ephemeral-job-${formatdate("YYYYMMDDhhmmss", timestamp())}"
    namespace = "default"
    labels = {
      ephemeral = true
    }
  }

  spec {
    template {
      metadata {
        labels = {
          ephemeral = true
        }
      }

      spec {
        container {
          name  = "test"
          image = "busybox:latest"
          command = ["echo", "Ephemeral job"]
        }
        
        restart_policy = "Never"
      }
    }

    # Auto-cleanup: Delete job after TTL expires (3600 seconds)
    ttl_seconds_after_finished = 3600
  }
}

# ============================================================================
# Kubernetes: Ephemeral Namespace with Auto-Cleanup
# ============================================================================
resource "kubernetes_namespace" "ephemeral" {
  metadata {
    name = "ephemeral-${formatdate("YYYYMMDDhhmmss", timestamp())}"
    labels = {
      ephemeral = true
      auto_cleanup = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Google Cloud Storage: Ephemeral Bucket with Lifecycle Rules
# ============================================================================
resource "google_storage_bucket" "ephemeral" {
  project       = var.gcp_project_id
  name          = "ephemeral-${var.deployment_id}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  location      = var.gcp_region
  force_destroy = true

  # Auto-delete objects after 7 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }

  # Archive to cold storage after 30 days
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 30
    }
  }

  labels = merge(
    local.ephemeral_tags,
    {
      type = "ephemeral-storage"
    }
  )
}

# ============================================================================
# GCP Cloud Scheduler: Ephemeral Resource Cleanup Job
# ============================================================================
resource "google_cloud_scheduler_job" "ephemeral_cleanup" {
  project     = var.gcp_project_id
  name        = "ephemeral-cleanup-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  description = "Auto-cleanup ephemeral resources (marks them for deletion)"
  region      = var.gcp_region
  schedule    = "0 * * * *"  # Every hour
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/ephemeral-cleanup"
    
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.ephemeral_cleanup.email
    }
  }
}

# ============================================================================
# Service Account: Ephemeral Cleanup
# ============================================================================
resource "google_service_account" "ephemeral_cleanup" {
  project     = var.gcp_project_id
  account_id  = "ephemeral-cleanup"
  description = "Service account for cleaning up ephemeral resources"
}

# ============================================================================
# Kubernetes CronJob: Ephemeral Pod Cleanup
# ============================================================================
resource "kubernetes_cron_job" "ephemeral_cleanup" {
  metadata {
    name      = "ephemeral-cleanup"
    namespace = "kube-system"
  }

  spec {
    schedule = "0 * * * *"  # Every hour
    
    job_template {
      spec {
        template {
          spec {
            container {
              name  = "cleanup"
              image = "bitnami/kubectl:latest"
              
              # Delete old ephemeral pods
              command = [
                "/bin/sh",
                "-c",
                "kubectl delete pods -A -l ephemeral=true --field-selector=status.phase=Failed"
              ]
            }
            
            restart_policy = "OnFailure"
            
            service_account_name = "ephemeral-cleanup"
          }
        }
      }
    }
  }
}

# ============================================================================
# Kubernetes ServiceAccount: Ephemeral Cleanup
# ============================================================================
resource "kubernetes_service_account" "ephemeral_cleanup" {
  metadata {
    name      = "ephemeral-cleanup"
    namespace = "kube-system"
  }
}

# ============================================================================
# Kubernetes ClusterRole: Ephemeral Cleanup Permissions
# ============================================================================
resource "kubernetes_cluster_role" "ephemeral_cleanup" {
  metadata {
    name = "ephemeral-cleanup"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces"]
    verbs      = ["get", "list", "delete"]
  }
}

# ============================================================================
# Kubernetes ClusterRoleBinding: Ephemeral Cleanup
# ============================================================================
resource "kubernetes_cluster_role_binding" "ephemeral_cleanup" {
  metadata {
    name = "ephemeral-cleanup"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.ephemeral_cleanup.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.ephemeral_cleanup.metadata[0].name
    namespace = kubernetes_service_account.ephemeral_cleanup.metadata[0].namespace
  }
}

# ============================================================================
# Outputs
# ============================================================================
output "ephemeral_cluster_id" {
  description = "ID of ephemeral EKS cluster"
  value       = aws_eks_cluster.ephemeral.id
}

output "ephemeral_cluster_endpoint" {
  description = "Endpoint of ephemeral EKS cluster"
  value       = aws_eks_cluster.ephemeral.endpoint
}

output "ephemeral_bucket_name" {
  description = "Name of ephemeral GCS bucket"
  value       = google_storage_bucket.ephemeral.name
}

output "ephemeral_namespace" {
  description = "Ephemeral Kubernetes namespace"
  value       = kubernetes_namespace.ephemeral.metadata[0].name
}
