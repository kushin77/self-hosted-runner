# Phase 0: Core NEXUS Infrastructure
# Immutable, Ephemeral, Idempotent, No-Ops Automated

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }

  backend "gcs" {
    bucket = "nexusshield-terraform-state"
    prefix = "phase0-core"
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

locals {
  environment = "production"
  labels = {
    environment = local.environment
    phase       = "phase0"
    managed-by  = "terraform"
    immutable   = true
    ephemeral   = true
    no-ops      = true
  }
}

# ============================================================================
# 1. CLOUD SQL: PostgreSQL Primary + Standby (Multi-Region HA)
# ============================================================================

resource "google_sql_database_instance" "primary" {
  name                = "nexus-postgres-primary-${lower(data.google_client_config.current.project)}"
  database_version    = "POSTGRES_15"
  region              = var.gcp_region
  deletion_protection = true

  settings {
    tier              = "db-custom-4-16384"
    availability_type = "REGIONAL"
    disk_size         = 100
    disk_type         = "PD_SSD"

    database_flags {
      name  = "rls"
      value = "on"
    }

    database_flags {
      name  = "max_connections"
      value = "500"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_statement"
      value = "all" # Audit all queries
    }

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      private_network = google_compute_network.main.id
      require_ssl     = true
    }

    insights_config {
      query_insights_enabled = true
      query_string_length    = 1024
    }

    user_labels = local.labels
  }
}

resource "google_sql_database_instance" "standby" {
  name                 = "nexus-postgres-standby-${lower(data.google_client_config.current.project)}"
  database_version     = "POSTGRES_15"
  region               = var.gcp_standby_region
  master_instance_name = google_sql_database_instance.primary.name

  replica_configuration {
    kind            = "REGIONAL"
    replica_type    = "FAILOVER"
    failover_target = true
  }

  depends_on = [
    google_sql_database_instance.primary
  ]
}

# Database: discovery
resource "google_sql_database" "discovery_db" {
  name       = "discovery_prod"
  instance   = google_sql_database_instance.primary.name
  depends_on = [google_sql_database_instance.primary]
}

# Database root user (disabled)
resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.primary.name
  type     = "BUILT_IN"
  password = random_password.postgres_root.result # Rotated automatically by Secret Manager
}

# Application user (ephemeral creds via workload identity)
resource "google_sql_user" "discovery_app" {
  name     = "discovery_app"
  instance = google_sql_database_instance.primary.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "random_password" "postgres_root" {
  length  = 32
  special = true
}

# ============================================================================
# 2. KAFKA: Multi-Partition Topics on Kubernetes
# ============================================================================

resource "kubernetes_namespace" "kafka" {
  metadata {
    name = "kafka"
    labels = merge(
      local.labels,
      {
        "pod-security.kubernetes.io/enforce" = "restricted"
      }
    )
  }
}

resource "kubernetes_stateful_set" "kafka_broker" {
  metadata {
    name      = "kafka-broker"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }

  spec {
    service_name = "kafka"
    replicas     = 3

    selector {
      match_labels = {
        app = "kafka-broker"
      }
    }

    template {
      metadata {
        labels = merge(
          local.labels,
          {
            app = "kafka-broker"
          }
        )
      }

      spec {
        service_account_name = "kafka"

        container {
          name  = "kafka"
          image = "confluentinc/cp-kafka:7.6.0"

          env {
            name = "KAFKA_BROKER_ID"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name  = "KAFKA_ZOOKEEPER_CONNECT"
            value = "zookeeper:2181"
          }

          env {
            name  = "KAFKA_ADVERTISED_LISTENERS"
            value = "PLAINTEXT://$(POD_IP):9092"
          }

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          env {
            name  = "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "PLAINTEXT:PLAINTEXT"
          }

          env {
            name  = "KAFKA_INTER_BROKER_LISTENER_NAME"
            value = "PLAINTEXT"
          }

          env {
            name  = "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR"
            value = "3"
          }

          env {
            name  = "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR"
            value = "2"
          }

          env {
            name  = "KAFKA_LOG_RETENTION_HOURS"
            value = "336" # 14 days
          }

          port {
            container_port = 9092
            name           = "kafka"
          }

          volume_mount {
            name       = "kafka-data"
            mount_path = "/var/lib/kafka/data"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "kafka-data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "standard"
        resources {
          requests = {
            storage = "50Gi"
          }
        }
      }
    }
  }
}

# ============================================================================
# 3. VAULT: Credential Injection Sidecar
# ============================================================================

resource "kubernetes_config_map" "vault_config" {
  metadata {
    name      = "vault-config"
    namespace = kubernetes_namespace.kafka.metadata[0].name
  }

  data = {
    "vault-agent-config.hcl" = file("${path.module}/vault-agent-config.hcl")
  }
}

# ============================================================================
# 4. GOOGLE SECRET MANAGER: Ephemeral Credentials
# ============================================================================

resource "google_secret_manager_secret" "db_connection_string" {
  secret_id = "nexus-db-connection-string"

  labels = local.labels

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_connection_string_version" {
  secret      = google_secret_manager_secret.db_connection_string.id
  secret_data = "postgresql://${google_sql_user.discovery_app.name}@${google_sql_database_instance.primary.private_ip_address}:5432/${google_sql_database.discovery_db.name}?sslmode=require"
}

resource "google_secret_manager_secret" "kafka_brokers" {
  secret_id = "nexus-kafka-brokers"

  labels = local.labels

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "kafka_brokers_version" {
  secret      = google_secret_manager_secret.kafka_brokers.id
  secret_data = "kafka-broker-0.kafka.svc.cluster.local:9092,kafka-broker-1.kafka.svc.cluster.local:9092,kafka-broker-2.kafka.svc.cluster.local:9092"
}

# ============================================================================
# 5. WORKLOAD IDENTITY: Ephemeral OIDC
# ============================================================================

resource "google_iam_workload_identity_pool" "nexus_pool" {
  provider                  = google-beta
  workload_identity_pool_id = "nexus-workload-pool"
  display_name              = "NEXUS Workload Identity Pool"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  provider                           = google-beta
  workload_identity_pool_id          = google_iam_workload_identity_pool.nexus_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.actor_type == 'repository'"
  disabled            = false
}

# ============================================================================
# 6. KMS: Encryption Keys
# ============================================================================

resource "google_kms_key_ring" "nexus_ring" {
  name     = "nexus-keys"
  location = var.gcp_region
}

resource "google_kms_crypto_key" "database" {
  name            = "database"
  key_ring        = google_kms_key_ring.nexus_ring.id
  rotation_period = "7776000s" # 90 days

  labels = local.labels
}

resource "google_kms_crypto_key" "kafka_messages" {
  name            = "kafka-messages"
  key_ring        = google_kms_key_ring.nexus_ring.id
  rotation_period = "2592000s" # 30 days

  labels = local.labels
}

# ============================================================================
# 7. VPC: Private Service Connection
# ============================================================================

resource "google_compute_network" "main" {
  name                    = "nexus-network"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  name          = "nexus-subnet"
  ip_cidr_range = "10.0.0.0/20"
  region        = var.gcp_region
  network       = google_compute_network.main.id

}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

# ============================================================================
# 8. CLOUD BUILD: CI/CD Pipeline (No GitHub Actions)
# ============================================================================

resource "google_cloudbuild_trigger" "main_push" {
  name        = "nexus-main-push"
  description = "Deploy NEXUS on main push (direct git→Terraform→Cloud Build)"
  filename    = "cloudbuild.nexus-phase0.yaml"

  github {
    owner = "kushin77"
    name  = "self-hosted-runner"
    push {
      branch = "^main$"
    }
  }

  service_account = google_service_account.cloud_build.id
}

# ============================================================================
# 9. SERVICE ACCOUNTS: Workload Identities
# ============================================================================

resource "google_service_account" "cloud_build" {
  account_id   = "nexus-cloud-build"
  display_name = "NEXUS Cloud Build"
}

resource "google_service_account" "discovery_ingestor" {
  account_id   = "nexus-discovery-ingestor"
  display_name = "NEXUS Discovery Event Ingestor"
}

resource "google_service_account" "kafka_consumer" {
  account_id   = "nexus-kafka-consumer"
  display_name = "NEXUS Kafka Consumer"
}

# IAM Bindings
resource "google_project_iam_member" "cloud_build_terraform" {
  project = var.gcp_project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_sql" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_secret_manager_secret_iam_member" "db_connection_read" {
  secret_id = google_secret_manager_secret.db_connection_string.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.discovery_ingestor.email}"
}

# ============================================================================
# 10. MONITORING: Cloud Logging + Audit Trails
# ============================================================================

resource "google_logging_project_sink" "audit_sink" {
  name        = "nexus-audit-trail"
  destination = google_storage_bucket.audit_logs.id

  filter = <<-EOT
    resource.type="cloud_sql_database" OR
    resource.type="k8s_pod" OR
    resource.type="cloud_build" OR
    severity >= "INFO"
  EOT

  unique_writer_identity = true
}

resource "google_storage_bucket" "audit_logs" {
  name          = "nexus-audit-logs-${var.gcp_project_id}"
  location      = var.gcp_region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
 
  labels = local.labels
}

 
# ============================================================================
# Data Sources
# ============================================================================

data "google_client_config" "current" {}

output "db_private_ip" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "kafka_brokers" {
  value = "kafka-broker-0.kafka.svc.cluster.local:9092,kafka-broker-1.kafka.svc.cluster.local:9092,kafka-broker-2.kafka.svc.cluster.local:9092"
}

