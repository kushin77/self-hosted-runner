pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "aws" {
    type = "iam"
    mount_path = "auth/aws"
    config = {
      role = "${VAULT_ROLE:-deployment}"
    }
  }

  sink "file" {
    config = { path = "/etc/vault/agent_token" }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address = "127.0.0.1:8201"
  tls_disable = true
}

template {
  source = "/etc/vault/templates/deployment.env.tpl"
  destination = "/opt/self-hosted-runner/.env.deployment"
  command = "/bin/chmod 600 /opt/self-hosted-runner/.env.deployment"
  perms = "0600"
}
