# Vault policy for runner token access
# Grants read access to runner registration tokens stored under secret/data/ci/self-hosted/*

path "secret/data/ci/self-hosted/*" {
  capabilities = ["read"]
}

# Additional paths (if using transit or other secrets engines) can be added here.
