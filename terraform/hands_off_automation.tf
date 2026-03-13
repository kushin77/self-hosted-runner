# Hands-Off Automation Scheduler Configuration
# Fully automated, no manual intervention required
# Runs credential rotation, deployments, and cleanup on schedule

locals {
  # Automation schedules (Cron format)
  schedules = {
    credential_rotation = "0 2 * * *"           # Daily 2:00 AM UTC
    vulnerability_scan  = "0 3 * * 0"           # Weekly, Sundays 3:00 AM UTC
    system_cleanup      = "0 4 * * *"           # Daily 4:00 AM UTC
    deployment_sync     = "*/30 * * * *"        # Every 30 minutes
    audit_trail_backup  = "0 */6 * * *"         # Every 6 hours
    health_check        = "*/5 * * * *"         # Every 5 minutes
  }

  # Environment configuration
  automation_env = {
    IMMUTABLE_LOG          = "/var/log/audit-trail.jsonl"
    CREDENTIAL_BACKEND     = "gsm,vault,kms,aws"
    CLEANUP_RETENTION_DAYS = 7
    DEPLOYMENT_TIMEOUT     = 1800  # 30 minutes
  }
}

# ============================================================================
# Google Cloud Scheduler: Credential Rotation (Daily 2 AM)
# ============================================================================
resource "google_cloud_scheduler_job" "credential_rotation" {
  project     = var.gcp_project_id
  name        = "credential-rotation-daily"
  description = "Rotate all credentials across GSM/Vault/KMS (no manual intervention)"
  region      = var.gcp_region
  schedule    = local.schedules.credential_rotation
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/${var.gcp_project_id}/credential-rotation"
    
    headers = {
      "Content-Type"  = "application/json"
      "Authorization" = "Bearer $(gcloud auth application-default print-access-token)"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Google Cloud Scheduler: Vulnerability Scan (Weekly)
# ============================================================================
resource "google_cloud_scheduler_job" "vulnerability_scan" {
  project     = var.gcp_project_id
  name        = "vulnerability-scan-weekly"
  description = "Scan container images and dependencies (automated, no approval needed)"
  region      = var.gcp_region
  schedule    = local.schedules.vulnerability_scan
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/${var.gcp_project_id}/vulnerability-scan"
    
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Google Cloud Scheduler: Ephemeral Resource Cleanup
# ============================================================================
resource "google_cloud_scheduler_job" "ephemeral_cleanup" {
  project     = var.gcp_project_id
  name        = "ephemeral-cleanup-hourly"
  description = "Clean up expired ephemeral resources (hands-off)"
  region      = var.gcp_region
  schedule    = "0 * * * *"  # Every hour
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/${var.gcp_project_id}/ephemeral-cleanup"
    
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Google Cloud Scheduler: Immutable Audit Trail Backup
# ============================================================================
resource "google_cloud_scheduler_job" "audit_trail_backup" {
  project     = var.gcp_project_id
  name        = "audit-trail-backup"
  description = "Backup immutable audit trail to S3 (idempotent)"
  region      = var.gcp_region
  schedule    = local.schedules.audit_trail_backup
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/${var.gcp_project_id}/audit-trail-backup"
    
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Google Cloud Scheduler: Infrastructure Health Check
# ============================================================================
resource "google_cloud_scheduler_job" "health_check" {
  project     = var.gcp_project_id
  name        = "infrastructure-health-check"
  description = "Verify all infrastructure is compliant (immutable/ephemeral/idempotent/no-ops)"
  region      = var.gcp_region
  schedule    = local.schedules.health_check
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloudfunctions.net/${var.gcp_project_id}/health-check"
    
    headers = {
      "Content-Type" = "application/json"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Google Cloud Scheduler: Direct Deployment Sync
# ============================================================================
resource "google_cloud_scheduler_job" "deployment_sync" {
  project     = var.gcp_project_id
  name        = "deployment-sync-periodic"
  description = "Sync direct deployments (no GitHub Actions/pull releases)"
  region      = var.gcp_region
  schedule    = local.schedules.deployment_sync
  time_zone   = "UTC"
  paused      = false

  http_target {
    http_method = "POST"
    uri         = "https://cloud-run-endpoint.run.app/v1/deploy"
    
    headers = {
      "Content-Type"  = "application/json"
      "Authorization" = "Bearer $(gcloud auth application-default print-access-token)"
    }

    oidc_token {
      service_account_email = google_service_account.scheduler_automation.email
    }
  }
}

# ============================================================================
# Service Account: Scheduler Automation
# ============================================================================
resource "google_service_account" "scheduler_automation" {
  project     = var.gcp_project_id
  account_id  = "scheduler-automation"
  description = "Service account for Cloud Scheduler hands-off automation"
}

# ============================================================================
# IAM: Scheduler Automation Permissions
# ============================================================================

# Allow scheduler to invoke Cloud Functions
resource "google_cloud_functions_iam_member" "scheduler_invoker" {
  for_each = toset([
    "credential-rotation",
    "vulnerability-scan",
    "ephemeral-cleanup",
    "audit-trail-backup",
    "health-check"
  ])

  cloud_function = each.key
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler_automation.email}"
}

# Allow scheduler to invoke Cloud Run
resource "google_cloud_run_service_iam_member" "scheduler_invoker" {
  project  = var.gcp_project_id
  service  = "direct-deploy-endpoint"
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_automation.email}"
}

# Allow scheduler to read secrets from GSM
resource "google_secret_manager_secret_iam_member" "scheduler_accessor" {
  for_each = toset([
    "github-deploy-token",
    "gcp-project-id",
    "aws-region",
    "database-password",
    "api-key"
  ])

  secret_id = each.key
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.scheduler_automation.email}"
}

# ============================================================================
# Kubernetes CronJob: Hands-Off Deployment Sync
# ============================================================================
resource "kubernetes_cron_job" "deployment_sync" {
  metadata {
    name      = "deployment-sync"
    namespace = "kube-system"
  }

  spec {
    schedule = local.schedules.deployment_sync
    
    job_template {
      spec {
        template {
          spec {
            container {
              name  = "sync"
              image = "google/cloud-sdk:latest"
              
              env {
                name  = "DEPLOYMENT_TOKEN"
                value_from {
                  secret_key_ref {
                    name = "deployment-secrets"
                    key  = "github-token"
                  }
                }
              }
              
              command = [
                "/bin/bash",
                "-c",
                "gcloud builds submit --config=cloudbuild.yaml ."
              ]
            }
            
            restart_policy = "OnFailure"
            
            service_account_name = "deployment-sync"
          }
        }
      }
    }
  }
}

# ============================================================================
# Kubernetes ServiceAccount: Deployment Sync
# ============================================================================
resource "kubernetes_service_account" "deployment_sync" {
  metadata {
    name      = "deployment-sync"
    namespace = "kube-system"
  }
}

# ============================================================================
# Kubernetes RBAC: Deployment Sync Permissions
# ============================================================================
resource "kubernetes_cluster_role" "deployment_sync" {
  metadata {
    name = "deployment-sync"
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets"]
    verbs      = ["get", "list", "patch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "deployment_sync" {
  metadata {
    name = "deployment-sync"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.deployment_sync.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.deployment_sync.metadata[0].name
    namespace = kubernetes_service_account.deployment_sync.metadata[0].namespace
  }
}

# ============================================================================
# CloudWatch Event: AWS Lambda Automation Trigger
# ============================================================================
resource "aws_cloudwatch_event_rule" "automation_trigger" {
  name                = "direct-deploy-automation"
  description         = "Trigger direct deployments (no GitHub Actions)"
  schedule_expression = "cron(0 2 * * ? *)"  # Daily 2 AM UTC

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "automation_lambda" {
  rule      = aws_cloudwatch_event_rule.automation_trigger.name
  target_id = "DirectDeploymentLambda"
  arn       = aws_lambda_function.direct_deploy.arn
  role_arn  = aws_iam_role.eventbridge_invoke_lambda.arn
}

# ============================================================================
# AWS Lambda: Direct Deployment Function
# ============================================================================
resource "aws_lambda_function" "direct_deploy" {
  filename      = "/tmp/direct-deploy-lambda.zip"
  function_name = "direct-deploy-automation"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 1800  # 30 minutes

  environment {
    variables = merge(
      local.automation_env,
      {
        GCP_PROJECT = var.gcp_project_id
        AWS_REGION  = var.aws_region
      }
    )
  }

  tags = var.tags
}

# ============================================================================
# IAM: EventBridge → Lambda
# ============================================================================
resource "aws_iam_role" "eventbridge_invoke_lambda" {
  name = "eventbridge-invoke-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_invoke_lambda" {
  name = "invoke-lambda"
  role = aws_iam_role.eventbridge_invoke_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.direct_deploy.arn
      }
    ]
  })
}

# ============================================================================
# IAM: Lambda Execution Role
# ============================================================================
resource "aws_iam_role" "lambda_execution" {
  name = "lambda-direct-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# Outputs
# ============================================================================
output "automation_schedules" {
  description = "Cloud Scheduler job schedules"
  value = {
    credential_rotation = local.schedules.credential_rotation
    vulnerability_scan  = local.schedules.vulnerability_scan
    system_cleanup      = local.schedules.system_cleanup
    deployment_sync     = local.schedules.deployment_sync
    audit_trail_backup  = local.schedules.audit_trail_backup
    health_check        = local.schedules.health_check
  }
}

output "scheduler_automation_email" {
  description = "Email of the scheduler automation service account"
  value       = google_service_account.scheduler_automation.email
}
