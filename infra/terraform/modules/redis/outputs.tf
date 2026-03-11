/**
 * Redis Memorystore Module - Outputs
 */

output "instance_name" {
  description = "Redis instance name"
  value       = google_redis_instance.main.name
}

output "host" {
  description = "Redis host IP address"
  value       = google_redis_instance.main.host
}

output "port" {
  description = "Redis port"
  value       = google_redis_instance.main.port
}

output "region" {
  description = "Redis region"
  value       = google_redis_instance.main.region
}

output "tier" {
  description = "Redis tier"
  value       = google_redis_instance.main.tier
}

output "memory_size_gb" {
  description = "Redis memory size in GB"
  value       = google_redis_instance.main.memory_size_gb
}

output "redis_version" {
  description = "Redis version"
  value       = google_redis_instance.main.redis_version
}

output "connection_string" {
  description = "Redis connection string (with auth if enabled)"
  value       = var.enable_auth && var.auth_password != "" ? "redis://:${var.auth_password}@${google_redis_instance.main.host}:${google_redis_instance.main.port}" : "redis://${google_redis_instance.main.host}:${google_redis_instance.main.port}"
  sensitive   = true
}

output "redis_config" {
  description = "Redis configuration object"
  value = {
    host     = google_redis_instance.main.host
    port     = google_redis_instance.main.port
    password = var.enable_auth && var.auth_password != "" ? var.auth_password : null
    ssl      = false
    db       = 0
  }
  sensitive = true
}
