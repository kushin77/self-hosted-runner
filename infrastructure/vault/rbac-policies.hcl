# Organization: ACME Corp
# Admin policy: Full access to org secrets
path "secret/org/acme/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Reader policy: Read-only access
path "secret/org/acme/*" {
  capabilities = ["read", "list"]
}

# Organization: Globex Inc
# Admin policy
path "secret/org/globex/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Reader policy
path "secret/org/globex/*" {
  capabilities = ["read", "list"]
}

# Cross-org denied
path "secret/org/*" {
  capabilities = ["deny"]
}
