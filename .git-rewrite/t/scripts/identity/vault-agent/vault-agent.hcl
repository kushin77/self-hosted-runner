pid_file = "/var/run/vault-agent.pid"

listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

auto_auth {
  method "oidc" {
    mount_path = "auth/jwt"
    config = {
      role = "{{env "VAULT_ROLE"}}"
      jwt_path = "/var/run/secrets/oidc/token"
    }
  }

  sink "file" {
    config = { path = "/var/run/secrets/vault/token" }
  }
}

cache {
  use_auto_auth_token = true
}

template {
  source = "/etc/vault-agent/templates/registry-creds.tpl"
  destination = "/etc/runner/registry-creds.json"
}
