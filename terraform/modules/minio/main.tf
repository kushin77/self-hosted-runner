terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

# MinIO Docker Image
resource "docker_image" "minio" {
  name          = "minio/minio:latest"
  keep_locally  = true
  pull_triggers = [timestamp()]
}

# Docker Network for MinIO
resource "docker_network" "minio_net" {
  name   = "minio-network"
  driver = "bridge"
}

# MinIO Container
resource "docker_container" "minio" {
  name      = "minio"
  image     = docker_image.minio.image_id
  hostname  = "minio.internal.elevatediq.com"
  must_run  = true
  restart_policy {
    condition = "unless-stopped"
  }

  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}",
    "MINIO_BROWSER_REDIRECT_URL=https://${var.minio_endpoint}:${var.minio_https_port}",
  ]

  ports {
    internal = 9000
    external = var.minio_port
  }

  ports {
    internal = 9001
    external = var.minio_console_port
  }

  volumes {
    host_path      = var.minio_data_path
    container_path = "/data"
  }

  networks_advanced {
    name = docker_network.minio_net.id
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }

  labels = {
    "io.elevatediq.service" = "minio"
    "io.elevatediq.managed" = "terraform"
  }
}

# MinIO Data Directory (ensure exists)
resource "null_resource" "minio_data_dir" {
  provisioner "local-exec" {
    command = "mkdir -p ${var.minio_data_path} && chmod 755 ${var.minio_data_path}"
  }
}

# MinIO S3 Bucket (via local-exec curl to MinIO API)
resource "null_resource" "minio_bucket" {
  depends_on = [docker_container.minio, null_resource.minio_data_dir]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      BUCKET_NAME="${var.minio_bucket_name}"
      ENDPOINT="http://localhost:${var.minio_port}"
      ROOT_USER="${var.minio_root_user}"
      ROOT_PASSWORD="${var.minio_root_password}"
      
      # Wait for MinIO to be healthy
      for i in {1..30}; do
        if curl -sS "$ENDPOINT/minio/health/live" >/dev/null 2>&1; then
          echo "MinIO health check passed"
          break
        fi
        echo "Waiting for MinIO... ($i/30)"
        sleep 2
      done
      
      # Create bucket using AWS CLI with MinIO endpoint
      aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --endpoint-url "$ENDPOINT" \
        --region us-east-1 \
        --access-key "$ROOT_USER" \
        --secret-key "$ROOT_PASSWORD" \
        || echo "Bucket already exists or creation failed (may be idempotent)"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'MinIO bucket cleanup handled via Ansible or manual deletion'"
  }
}

# Output MinIO connection details
locals {
  minio_endpoint = "https://${var.minio_endpoint}:${var.minio_https_port}"
}
