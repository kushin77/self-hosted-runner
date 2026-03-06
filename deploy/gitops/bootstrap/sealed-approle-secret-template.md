# SealedSecret (AppRole) bootstrap template

This file shows how to create a Kubernetes `Secret` for Vault AppRole and then seal it with `kubeseal` to produce a `SealedSecret` safe to store in Git.

Do NOT commit unsealed secrets. Use `kubeseal` with your cluster public key to create a sealed secret.

1) Create a plaintext secret locally (DO NOT COMMIT):

```bash
kubectl create secret generic vault-approle-secret \
  --namespace gitops \
  --from-literal=secretId='<VAULT_SECRET_ID_FROM_VAULT>' \
  --dry-run=client -o yaml > vault-approle-secret.yaml
```

2) Seal it using `kubeseal` (requires Sealed Secrets controller public key):

```bash
kubeseal --controller-name=sealed-secrets --controller-namespace=kube-system \
  --format yaml < vault-approle-secret.yaml > sealed-vault-approle-secret.yaml
```

3) Commit only `sealed-vault-approle-secret.yaml` into `deploy/gitops/bootstrap/` if you choose to bootstrap secrets via sealed-secrets.

Template of the unsealed Secret (for reference only):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-approle-secret
  namespace: gitops
type: Opaque
stringData:
  secretId: "<VAULT_SECRET_ID_PLACEHOLDER>"
```
