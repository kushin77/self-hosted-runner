/**
 * Cloud SQL Module - Outputs
 */

output "instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "instance_connection_name" {
  description = "Cloud SQL instance connection name (for Cloud SQL Proxy)"
  value       = google_sql_database_instance.main.connection_name
}

output "private_ip_address" {
  description = "Private IP address of the instance"
  value       = google_sql_database_instance.main.private_ip_address
}

output "database_name" {
  description = "Name of the main database"
  value       = google_sql_database.main.name
}

output "root_user_name" {
  description = "Root database user"
  value       = google_sql_user.root.name
}

output "app_user_name" {
  description = "Application database user"
  value       = google_sql_user.app_user.name
}

output "app_user_password" {
  description = "Application user password"
  value       = random_password.app_user_password.result
  sensitive   = true
}

output "replica_instance_name" {
  description = "HA replica instance name (if enabled)"
  value       = try(google_sql_database_instance.replica[0].name, null)
}

output "replica_connection_name" {
  description = "HA replica connection name (if enabled)"
  value       = try(google_sql_database_instance.replica[0].connection_name, null)
}

output "backup_location" {
  description = "Backup storage location"
  value       = var.backup_location
}
