###############################################################################
# Cloud Firestore Database - Production Deployment
#
# Purpose: NoSQL database for Portal MVP (bypasses Cloud SQL org policy constraints)
# Advantages: 
#   - No VPC peering required (bypasses restrictVpcPeering constraint)
#   - No public/private IP assignment (bypasses sql.restrictPublicIp)
#   - Fully managed with automatic scaling
#   - Built-in authentication via Firebase/IAM
#   - Real-time capabilities with Cloud Functions
#   - Regional redundancy (us-central1)
#
# Deployment: Enabled by default with use_firestore=true in terraform.tfvars
###############################################################################

# Create Firestore database (NoSQL alternative to Cloud SQL)
resource "google_firestore_database" "portal_db" {
  count = var.use_firestore ? 1 : 0

  project          = var.gcp_project_id
  name             = "(default)"
  location_id      = var.gcp_region
  type             = "FIRESTORE_NATIVE"
  concurrency_mode = "OPTIMISTIC"

  depends_on = [
    google_project_service.firestore_api
  ]
}

# Enable Firestore API
resource "google_project_service" "firestore_api" {
  count = var.use_firestore ? 1 : 0

  project            = var.gcp_project_id
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

# IAM: Service Account access to Firestore
resource "google_project_iam_member" "portal_backend_firestore_user" {
  count = var.use_firestore ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.portal_backend.email}"

  depends_on = [
    google_firestore_database.portal_db
  ]
}

# Outputs for Firestore
output "firestore_database_name" {
  value       = var.use_firestore ? google_firestore_database.portal_db[0].name : null
  description = "Name of the Firestore database (only when use_firestore=true)"
}

output "firestore_location" {
  value       = var.use_firestore ? google_firestore_database.portal_db[0].location_id : null
  description = "Location of the Firestore database"
}

output "firestore_endpoint" {
  value       = var.use_firestore ? "projects/${var.gcp_project_id}/databases/(default)" : null
  description = "Firestore database endpoint for client connections"
}
