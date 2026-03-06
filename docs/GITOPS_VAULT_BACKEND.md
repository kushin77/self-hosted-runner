GitOps Vault backend (ClusterSecretStore + AppRole)
-----------------------------------------------

This document describes a secure pattern to allow the ExternalSecrets operator to fetch secrets from Vault using AppRole and a Kubernetes `ClusterSecretStore` named `vault-backend`.

Important: Never check `secretId` values or Vault `secret_id` into git. Kubernetes Secrets referenced by the `ClusterSecretStore` must be created securely in-cluster (sealed, created via CI, or injected by operators).

1) Create AppRole in Vault

Run in a secure environment with Vault CLI and appropriate privileges:

```bash
# Create a policy (example)
vault policy write gitops-minio - <<'EOF'
path "secret/data/minio/*" {
  capabilities = ["read"]
}
EOF

# Create an AppRole bound to the policy
vault write auth/approle/role/gitops-minio token_policies="gitops-minio" token_ttl="1h" secret_id_ttl="24h"

# Fetch role_id and secret_id (secret_id should be stored securely and never committed)
vault read -format=json auth/approle/role/gitops-minio/role-id
vault write -format=json -f auth/approle/role/gitops-minio/secret-id
```

2) Create Kubernetes Secret for `secretId`

Create `vault-approle-secret` in the `gitops` namespace with the `secretId` value (do not commit):

```bash
kubectl create secret generic vault-approle-secret \
  --namespace gitops \
  --from-literal=secretId='<SECRET_ID_FROM_VAULT>'
```

3) Configure `ClusterSecretStore`

Use the template at `deploy/gitops/bootstrap/cluster-secret-store.yaml`. Replace `roleId` with the value from Vault (this is not secret) and ensure the `secretRef.name` matches the k8s secret above.

4) ExternalSecret example

See `deploy/gitops/external-secrets/example-externalsecret.yaml` for how to map `secret/data/minio/ci` properties to a Kubernetes Secret.

5) Permissions and rotation

- Use short TTLs for AppRole `secret_id` and rotate regularly.
- Store any secret material in an external secure store or vault; consider using sealed-secrets or an operator for bootstrap automation.
