# Production Environment Configuration
# Full-featured setup with HA, backups, monitoring, and disaster recovery

project_id = "your-gcp-project-id"  # Replace with actual project ID
region     = "us-central1"
environment = "prod"
service_name = "nexus-shield"

# Container Images
backend_image  = "gcr.io/your-project/nexus-shield-backend:stable"
frontend_image = "gcr.io/your-project/nexus-shield-frontend:stable"

# Compute - Large footprint for production
backend_memory  = "2Gi"
backend_cpu     = "2"
frontend_memory = "1Gi"
frontend_cpu    = "2"

# Autoscaling - High availability
cloud_run_min_instances = 2      # Always have 2+ instances
cloud_run_max_instances = 20     # High max for traffic spikes

# Database - Multi-zone with full HA
database_machine_type    = "db-custom-4-16384"   # 4 vCPU, 16GB RAM
database_version         = "15"
enable_database_ha       = true   # HA mandatory for prod
backup_location          = "us"

# Cache - Standard tier (replication) with larger memory
redis_tier           = "standard"
redis_memory_size_gb = 8      # Large allocation for prod cache
redis_version        = "7.x"

# Security & Features
enable_encryption    = true   # KMS encryption mandatory
enable_wif           = true   # WIF for GitHub Actions
enable_nat_gateway   = true   # NAT for outbound traffic
enable_cdn           = true   # CDN for frontend global distribution

# Labels
labels = {
  managed_by  = "terraform"
  project     = "nexus-shield"
  environment = "prod"
  cost_center = "operations"
  sla         = "99.95%"
}
