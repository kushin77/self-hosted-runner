# Vault policy granting read access to deployment fields
path "secret/data/deployment/fields/*" {
  capabilities = ["read","list"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
