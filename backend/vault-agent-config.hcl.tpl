# Minimal Vault Agent config template (placeholder)
# This file is used by the Docker build as a template. Fill with secure values in production.

pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path = "/var/run/secrets/vault/role_id"
      secret_id_file_path = "/var/run/secrets/vault/secret_id"
    }
  }
  sink "file" {
    config = {
      path = "/var/run/secrets/vault/token"
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}
