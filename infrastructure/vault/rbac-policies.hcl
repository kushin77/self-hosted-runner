# Vault RBAC Policies for Multi-Tenant Provisioning

# Admin policy (provisioner-admin)
path "auth/approle/role/provisioner-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/provisioner/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/provisioner/*" {
  capabilities = ["list"]
}

path "sys/audit" {
  capabilities = ["read", "list"]
}

---
# Per-org provisioner policy (provisioner-worker-org-${org_name})
# Applied dynamically by provisioner-worker for multi-tenancy

path "secret/data/provisioner/{{ .org_name }}/*" {
  capabilities = ["read", "list"]
}

path "secret/data/terraform/{{ .org_name }}/*" {
  capabilities = ["read", "list"]
}

path "auth/token/create" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

# Managed-auth policy (managed-auth-role)
path "auth/approle/role/managed-auth-*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "secret/data/provisioner/*" {
  capabilities = ["read", "list"]
}

path "sys/audit" {
  capabilities = ["read", "list"]
}

---
# Audit logging policy (compliance-auditor)
path "sys/audit" {
  capabilities = ["read", "list"]
}

path "sys/audit/*" {
  capabilities = ["read", "list"]
}

path "auth/approle/role/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/provisioner/*" {
  capabilities = ["list"]
}
