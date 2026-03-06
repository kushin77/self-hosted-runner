Harbor Integration wrapper
-------------------------

This wrapper provisions Postgres and Redis (using the local modules in `../postgres` and `../redis`) and copies the generated credentials into the Harbor namespace by creating Kubernetes secrets.

Usage:

1. From the `terraform/provision/harbor-integration` directory run:

```bash
terraform init
terraform apply -var "kubeconfig_path=~/.kube/config" -var "harbor_namespace=harbor"
```

2. After apply, the secrets `harbor-db-password` and `harbor-redis-password` will be present in the Harbor namespace and the Harbor chart can be installed using those secret names.

Notes:
- This wrapper invokes the local modules; ensure relative paths remain correct if moving files.
- The module outputs the created secret names.
