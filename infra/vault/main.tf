terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "null" {}

resource "null_resource" "vault_bootstrap_placeholder" {
  triggers = {
    timestamp = timestamp()
  }
  provisioner "local-exec" {
    command = "echo 'Vault bootstrap placeholder. Replace with real Helm/K8s deployment.'"
  }
}

output "vault_bootstrap_note" {
  value = "Replace this module with real Vault provisioning. Returns: vault_addr, vault_namespace"
}
