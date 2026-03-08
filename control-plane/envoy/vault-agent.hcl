auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "control-plane-role"
    }
  }
  sink "file" {
    config = {
      path = "/var/run/vault/token"
    }
  }
}

template {
  source      = "/etc/vault/templates/cert.tpl"
  destination = "/etc/envoy/tls/server.crt"
  perms       = "0640"
}

template {
  source      = "/etc/vault/templates/key.tpl"
  destination = "/etc/envoy/tls/server.key"
  perms       = "0640"
}

template {
  source      = "/etc/vault/templates/ca.tpl"
  destination = "/etc/envoy/tls/ca.crt"
  perms       = "0640"
}
