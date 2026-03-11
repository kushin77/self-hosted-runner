/**
 * Root Configuration - Main Module Orchestration
 */

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

  backend "gcs" {
    # Configure via backend config file or terraform init
    # bucket         = "nexus-shield-terraform-state-{env}-{project}"
    # prefix         = "terraform/state"
    # encryption_key = "..." (base64-encoded)
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
# LOCAL VALUES
# ============================================================================

locals {
  common_labels = merge(
    var.labels,
    {
      environment = var.environment
      service     = var.service_name
      region      = var.region
    }
  )
}

# ============================================================================
# IAM MODULE
# ============================================================================

module "iam" {
  source = "./modules/iam"

  project_id   = var.project_id
  environment  = var.environment
  service_name = var.service_name
  labels       = local.common_labels

  enable_wif = var.enable_wif
}

# ============================================================================
# VPC NETWORKING MODULE
# ============================================================================

module "vpc" {
  source = "./modules/vpc_networking"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  service_name = var.service_name
  labels       = local.common_labels

  enable_nat = var.enable_nat_gateway
}

# ============================================================================
# CLOUD SQL MODULE
# ============================================================================

module "cloud_sql" {
  source = "./modules/cloud_sql"

  project_id           = var.project_id
  region               = var.region
  environment          = var.environment
  service_name         = var.service_name
  labels               = local.common_labels

  database_machine_type       = var.database_machine_type
  database_version            = var.database_version
  enable_high_availability    = var.enable_database_ha
  backup_location             = var.backup_location
  network_id                  = module.vpc.network_id
  root_password               = var.database_root_password
}

# ============================================================================
# REDIS MODULE
# ============================================================================

module "redis" {
  source = "./modules/redis"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  service_name = var.service_name
  labels       = local.common_labels

  tier                 = var.redis_tier
  memory_size_gb       = var.redis_memory_size_gb
  redis_version        = var.redis_version
  network_id           = module.vpc.network_id
  auth_password        = var.redis_auth_password
  enable_persistence   = true
  enable_auth          = true
}

# ============================================================================
# STORAGE MODULE
# ============================================================================

module "storage" {
  source = "./modules/storage"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  service_name = var.service_name
  labels       = local.common_labels

  enable_encryption                  = var.enable_encryption
  service_account_email              = module.iam.backend_service_account_email
  terraform_service_account_email    = module.iam.terraform_service_account_email
}

# ============================================================================
# CLOUD RUN MODULE
# ============================================================================

module "cloud_run" {
  source = "./modules/cloud_run"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  service_name = var.service_name
  labels       = local.common_labels

  backend_image              = var.backend_image
  frontend_image             = var.frontend_image
  backend_memory             = var.backend_memory
  backend_cpu                = var.backend_cpu
  frontend_memory            = var.frontend_memory
  frontend_cpu               = var.frontend_cpu
  min_instances              = var.cloud_run_min_instances
  max_instances              = var.cloud_run_max_instances
  service_account_email      = module.iam.backend_service_account_email
  vpc_connector_name         = module.vpc.vpc_connector_name
  environment_variables      = var.backend_env_vars
  enable_cdn                 = var.enable_cdn
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "iam_outputs" {
  description = "IAM module outputs"
  value = {
    backend_service_account_email        = module.iam.backend_service_account_email
    frontend_service_account_email       = module.iam.frontend_service_account_email
    terraform_service_account_email      = module.iam.terraform_service_account_email
    workload_identity_pool_id            = module.iam.workload_identity_pool_id
    workload_identity_provider_id        = module.iam.workload_identity_provider_id
  }
}

output "vpc_outputs" {
  description = "VPC module outputs"
  value = {
    network_id                = module.vpc.network_id
    network_name              = module.vpc.network_name
    primary_subnet_id         = module.vpc.primary_subnet_id
    vpc_connector_id          = module.vpc.vpc_connector_id
    vpc_connector_name        = module.vpc.vpc_connector_name
    router_id                 = module.vpc.router_id
    nat_ip                    = module.vpc.nat_ip
  }
}

output "cloud_sql_outputs" {
  description = "Cloud SQL module outputs"
  value = {
    instance_name              = module.cloud_sql.instance_name
    instance_connection_name   = module.cloud_sql.instance_connection_name
    private_ip_address         = module.cloud_sql.private_ip_address
    database_name              = module.cloud_sql.database_name
    root_user_name             = module.cloud_sql.root_user_name
    app_user_name              = module.cloud_sql.app_user_name
    replica_instance_name      = module.cloud_sql.replica_instance_name
    replica_connection_name    = module.cloud_sql.replica_connection_name
  }
}

output "redis_outputs" {
  description = "Redis module outputs"
  value = {
    instance_name              = module.redis.instance_name
    host                       = module.redis.host
    port                       = module.redis.port
    region                     = module.redis.region
    tier                       = module.redis.tier
    memory_size_gb             = module.redis.memory_size_gb
    redis_version              = module.redis.redis_version
  }
}

output "storage_outputs" {
  description = "Storage module outputs"
  value = {
    terraform_state_bucket_name = module.storage.terraform_state_bucket_name
    artifacts_bucket_name       = module.storage.artifacts_bucket_name
    backups_bucket_name         = module.storage.backups_bucket_name
    audit_logs_bucket_name      = module.storage.audit_logs_bucket_name
    kms_key_ring_id             = module.storage.kms_key_ring_id
    kms_crypto_key_id           = module.storage.kms_crypto_key_id
  }
}

output "cloud_run_outputs" {
  description = "Cloud Run module outputs"
  value = {
    backend_service_name       = module.cloud_run.backend_service_name
    backend_service_url        = module.cloud_run.backend_service_url
    frontend_service_name      = module.cloud_run.frontend_service_name
    frontend_service_url       = module.cloud_run.frontend_service_url
  }
}

output "deployment_summary" {
  description = "Complete deployment summary"
  value = {
    project_id                          = var.project_id
    region                              = var.region
    environment                         = var.environment
    service_name                        = var.service_name
    backend_api_url                     = module.cloud_run.backend_service_url
    frontend_url                        = module.cloud_run.frontend_service_url
    database                            = "${module.cloud_sql.instance_name} (PostgreSQL ${var.database_version})"
    cache                               = "${module.redis.instance_name} (${var.redis_tier} tier, ${var.redis_memory_size_gb}GB)"
    terraform_state_bucket              = module.storage.terraform_state_bucket_name
    high_availability_enabled           = var.enable_database_ha
    workload_identity_enabled           = var.enable_wif
  }
}
