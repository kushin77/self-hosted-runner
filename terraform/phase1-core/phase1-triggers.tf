terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
  backend "local" {
    path = "phase1.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ============================================================================
# CLOUD BUILD TRIGGERS FOR PHASE 1 (Direct Git Webhook, NO GitHub Actions)
# ============================================================================

# Cloud Build Trigger for main branch pushes
resource "google_cloudbuild_trigger" "phase1_main" {
  name       = "phase1-main-push"
  filename   = "cloudbuild.nexus-phase1.yaml"
  project    = var.project_id
  
  github {
    owner = var.github_owner != "" ? var.github_owner : "kushin77"
    name  = var.github_repo != "" ? var.github_repo : "self-hosted-runner"
    push {
      branch = "^main$"
    }
  }

  substitutions = {
    "_ARTIFACT_REGISTRY"  = google_artifact_registry_repository.nexus_images.repository_id
    "_GKE_CLUSTER"       = var.gke_cluster_name
    "_K8S_NAMESPACE"     = var.namespace
    "_REGION"            = var.region
    "_PROJECT_ID"        = var.project_id
  }
}

# Cloud Build Trigger for staging branch pushes
resource "google_cloudbuild_trigger" "phase1_staging" {
  name       = "phase1-staging-push"
  filename   = "cloudbuild.nexus-phase1.yaml"
  project    = var.project_id
  
  github {
    owner = var.github_owner != "" ? var.github_owner : "kushin77"
    name  = var.github_repo != "" ? var.github_repo : "self-hosted-runner"
    push {
      branch = "^staging$"
    }
  }

  substitutions = {
    "_ARTIFACT_REGISTRY"  = google_artifact_registry_repository.nexus_images.repository_id
    "_GKE_CLUSTER"       = var.gke_cluster_name
    "_K8S_NAMESPACE"     = var.namespace
    "_REGION"            = var.region
    "_PROJECT_ID"        = var.project_id
  }
}

# ============================================================================
# WEBHOOK INGESTION SERVICE (Cloud Run)
# ============================================================================

# Cloud Run service for webhook ingestion (placeholder - actual image will be pushed)
resource "google_cloud_run_service" "webhook_ingestion" {
  name     = "nexus-webhook-ingestion"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.webhook_sa.email
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.nexus_images.repository_id}/nexus-webhook:latest"
        
        env {
          name  = "PORT"
          value = "8080"
        }
        
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
      }
      
      timeout_seconds = 300
    }
    
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "100"
        "run.googleapis.com/client-name" = "terraform"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.cloud_run,
    google_service_account.webhook_sa
  ]
}

# Cloud Run IAM - allow unauthenticated webhook access
resource "google_cloud_run_service_iam_member" "webhook_public" {
  service  = google_cloud_run_service.webhook_ingestion.name
  location = google_cloud_run_service.webhook_ingestion.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# SERVICE ACCOUNTS FOR DIFFERENT CI/CD SYSTEMS
# ============================================================================

resource "google_service_account" "webhook_sa" {
  account_id   = "nexus-webhook-sa"
  display_name = "Nexus Webhook Ingestion Service Account"
  project      = var.project_id
}

resource "google_service_account" "jenkins_sa" {
  account_id   = "nexus-jenkins-webhook"
  display_name = "Jenkins Webhook Service Account"
  project      = var.project_id
}

resource "google_service_account" "bitbucket_sa" {
  account_id   = "nexus-bitbucket-webhook"
  display_name = "Bitbucket Webhook Service Account"
  project      = var.project_id
}

resource "google_service_account" "gitlab_sa" {
  account_id   = "nexus-gitlab-webhook"
  display_name = "GitLab Webhook Service Account"
  project      = var.project_id
}

# ============================================================================
# ARTIFACT REGISTRY
# ============================================================================

resource "google_artifact_registry_repository" "nexus_images" {
  location      = var.artifact_registry_location
  repository_id = "nexus"
  description   = "Container images for Nexus Discovery Phase 1"
  format        = "DOCKER"
  project       = var.project_id

  cleanup_policies {
    id            = "delete-unstable"
    action        = "DELETE"
    condition {
      tag_state             = "UNTAGGED"
      newer_than            = "2592000s"  # 30 days
    }
  }
}

# ============================================================================
# STORAGE BUCKETS FOR AUDIT LOGS AND REPORTS
# ============================================================================

resource "google_storage_bucket" "phase1_reports" {
  name          = "${var.project_id}-phase1-reports"
  location      = "US-CENTRAL1"
  force_destroy = false
  project       = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age                   = 90
      matches_storage_class = ["STANDARD"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
  }
}

resource "google_storage_bucket" "phase1_audit" {
  name          = "${var.project_id}-phase1-audit"
  location      = "US-CENTRAL1"
  force_destroy = false
  project       = var.project_id

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

# ============================================================================
# IAM BINDINGS FOR SERVICE ACCOUNTS
# ============================================================================

# Webhook SA - read secrets and write to Pub/Sub
resource "google_secret_manager_secret_iam_member" "webhook_secrets" {
  secret_id = "projects/${var.project_id}/secrets/nexus-secrets"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.webhook_sa.email}"
}

# Webhook SA - write logs
resource "google_project_iam_member" "webhook_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.webhook_sa.email}"
}

# Jenkins SA - run Cloud Build jobs
resource "google_project_iam_member" "jenkins_cloud_build" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

# Bitbucket SA - run Cloud Build jobs
resource "google_project_iam_member" "bitbucket_cloud_build" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.bitbucket_sa.email}"
}

# GitLab SA - run Cloud Build jobs
resource "google_project_iam_member" "gitlab_cloud_build" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.editor"
  member  = "serviceAccount:${google_service_account.gitlab_sa.email}"
}

# ============================================================================
# GCP SERVICE ENABLEMENT
# ============================================================================

resource "google_project_service" "cloud_build" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secret_manager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project = var.project_id
  service = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"
  disable_on_destroy = false
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "phase1_trigger_ids" {
  description = "Cloud Build trigger IDs for Phase 1"
  value = {
    main_push = try(google_cloudbuild_trigger.phase1_main.id, null)
    staging_push = try(google_cloudbuild_trigger.phase1_staging.id, null)
  }
}

output "webhook_service_url" {
  description = "Cloud Run webhook service URL"
  value = try(google_cloud_run_service.webhook_ingestion.status[0].url, "")
}

output "jenkins_webhook_url" {
  description = "Webhook URL for Jenkins integration"
  value = "${try(google_cloud_run_service.webhook_ingestion.status[0].url, "")}/jenkins"
}

output "bitbucket_webhook_url" {
  description = "Webhook URL for Bitbucket integration"
  value = "${try(google_cloud_run_service.webhook_ingestion.status[0].url, "")}/bitbucket"
}

output "gitlab_webhook_url" {
  description = "Webhook URL for GitLab integration"
  value = "${try(google_cloud_run_service.webhook_ingestion.status[0].url, "")}/gitlab"
}

output "artifact_registry" {
  description = "Artifact Registry repository name"
  value = google_artifact_registry_repository.nexus_images.repository_id
}
