pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "control-plane-role"
    }
  }
  sink "file" {
    config = {
      path = "/var/run/vault-token"
    }
  }
}

template {
  source = "/etc/vault/templates/cert.tpl"
  destination = "/etc/envoy/tls/server.crt"
}
