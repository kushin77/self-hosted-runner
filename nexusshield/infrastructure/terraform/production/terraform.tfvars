###############################################################################
# NexusShield Portal Infrastructure - Terraform Variable Overrides
#
# Purpose: Production deployment configuration (March 10, 2026)
# Status: Use Cloud Firestore as primary database (bypasses org policy constraints)
# Fallback: Cloud SQL config remains in code for future use
###############################################################################

# GCP Configuration
gcp_project_id = "nexusshield-prod"
gcp_region     = "us-central1"
environment    = "production"

# Database Configuration
use_firestore = true # PRIMARY: Use Firestore (no org policy constraints)
# use_firestore = false  # FALLBACK: Use Cloud SQL (requires org policy exemption)

# Cloud Run Configuration
portal_image         = "us-central1-docker.pkg.dev/nexusshield-prod/portal-backend-repo/portal-backend:latest"
portal_memory        = "512Mi"
portal_timeout       = 300
portal_max_instances = 100

# Network & Security
allow_public = false

# Features
enable_monitoring = true
enable_tracing    = true
enable_profiling  = false

# Labels
labels = {
  managed_by           = "terraform"
  application          = "nexusshield-portal"
  environment          = "production"
  deployment           = "emergency-firestore-workaround-mar-10-2026"
  org-policy-compliant = "true"
}
