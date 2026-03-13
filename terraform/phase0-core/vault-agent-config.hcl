## Vault Agent Config stub
## This file is intentionally minimal for validation purposes.
auto_auth {
  method "gcp" {}
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = true
}
