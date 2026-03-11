# Development Environment Configuration
# Lightweight setup with autoscaling and minimal HA

project_id = "your-gcp-project-id"  # Replace with actual project ID
region     = "us-central1"
environment = "dev"
service_name = "nexus-shield"

# Container Images
backend_image  = "gcr.io/your-project/nexus-shield-backend:latest"
frontend_image = "gcr.io/your-project/nexus-shield-frontend:latest"

# Compute - Small footprint for development
backend_memory  = "512Mi"
backend_cpu     = "0.5"
frontend_memory = "256Mi"
frontend_cpu    = "0.5"

# Autoscaling - Lower bounds for cost efficiency
cloud_run_min_instances = 0      # Scale to zero when idle
cloud_run_max_instances = 3      # Lower max for dev

# Database - Single-zone, smaller machine
database_machine_type    = "db-custom-1-4096"  # 1 vCPU, 4GB RAM
database_version         = "15"
enable_database_ha       = false  # HA not needed for dev
backup_location          = "us"

# Cache - Basic tier (no replication)
redis_tier           = "basic"
redis_memory_size_gb = 1  # Small for dev
redis_version        = "7.x"

# Security & Features
enable_encryption    = false  # KMS optional for dev
enable_wif           = true   # Always enable WIF
enable_nat_gateway   = true   # Allow outbound access for updates
enable_cdn           = false  # CDN not needed for dev

# Labels
labels = {
  managed_by  = "terraform"
  project     = "nexus-shield"
  environment = "dev"
  cost_center = "engineering"
}
