copy-secret-to-namespace.sh
---------------------------

Small helper to copy an existing Kubernetes secret from one namespace to another.

Prerequisites:
- `kubectl` configured to access your cluster
- `jq` available on PATH

Usage:

```bash
./scripts/copy-secret-to-namespace.sh harbor-db-password postgres default
# copies the secret 'harbor-db-password' from namespace 'postgres' into 'default'
```

Notes:
- This script preserves the secret data as-is and removes cluster-assigned metadata before applying into the target namespace.
- Use this as a safe convenience for installing Harbor in a different namespace than the provisioned Postgres/Redis modules.
