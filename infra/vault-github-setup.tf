# Vault GitHub OIDC setup
# Purpose: Enable GitHub OIDC authentication to Vault
# GitHub Actions gets ephemeral Vault token via OIDC (no long-lived tokens)

# Enable JWT auth method
resource "vault_jwt_auth_backend" "github" {
  path               = "auth/jwt"
  type               = "jwt"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  oidc_client_id     = "sts.amazonaws.com"  # GitHub Actions standard audience
  bound_issuer       = "https://token.actions.githubusercontent.com"

  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "1h"
  }
}

# GitHub OIDC role in Vault
resource "vault_jwt_auth_backend_role" "github_actions" {
  backend   = vault_jwt_auth_backend.github.path
  role_name = "github-actions"

  bound_audiences = ["sts.amazonaws.com"]
  user_claim      = "actor"

  token_policies = ["github-actions-policy"]

  token_ttl         = 3600   # 1 hour
  token_max_ttl     = 3600   # 1 hour
  token_num_uses    = 0      # Unlimited uses within TTL
  token_bound_cidrs = []     # No IP restrictions
}

# Policy for GitHub Actions
resource "vault_policy" "github_actions" {
  name = "github-actions-policy"

  policy = <<EOH
# Allow reading secrets from KV v2
path "secret/data/credential_*" {
  capabilities = ["read", "list"]
}

path "secret/data/token_*" {
  capabilities = ["read", "list"]
}

# Allow self-renewal of token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow revocation of token
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
EOH
}

# Vault KV v2 secrets engine (for credentials)
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets for credentials"
}

# Example secrets storage (optional - can be populated via API)
# resource "vault_kv_secret_v2" "example_credential" {
#   mount = vault_mount.kv.path
#   name  = "credential_example"
#
#   data_json = jsonencode({
#     value = "example-secret-value"
#   })
# }

# Outputs
output "vault_jwt_auth_path" {
  value = vault_jwt_auth_backend.github.path
}

output "vault_github_role" {
  value = vault_jwt_auth_backend_role.github_actions.role_name
}

output "vault_kv_path" {
  value = vault_mount.kv.path
}
