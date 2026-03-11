# Staging Environment Configuration
# Production-like setup with balanced HA and monitoring

project_id = "your-gcp-project-id"  # Replace with actual project ID
region     = "us-central1"
environment = "staging"
service_name = "nexus-shield"

# Container Images
backend_image  = "gcr.io/your-project/nexus-shield-backend:staging"
frontend_image = "gcr.io/your-project/nexus-shield-frontend:staging"

# Compute - Medium footprint for staging
backend_memory  = "1Gi"
backend_cpu     = "1"
frontend_memory = "512Mi"
frontend_cpu    = "1"

# Autoscaling - Balanced for staging load
cloud_run_min_instances = 1      # Keep at least one running
cloud_run_max_instances = 5      # Moderate max for staging

# Database - Multi-zone with HA
database_machine_type    = "db-custom-2-8192"    # 2 vCPU, 8GB RAM
database_version         = "15"
enable_database_ha       = true   # HA for staging
backup_location          = "us"

# Cache - Standard tier (replication)
redis_tier           = "standard"
redis_memory_size_gb = 4      # Standard allocation
redis_version        = "7.x"

# Security & Features
enable_encryption    = true   # KMS enabled for staging
enable_wif           = true   # WIF for GitHub Actions
enable_nat_gateway   = true   # Allow outbound for updates
enable_cdn           = true   # CDN for frontend optimization

# Labels
labels = {
  managed_by  = "terraform"
  project     = "nexus-shield"
  environment = "staging"
  cost_center = "engineering"
}
