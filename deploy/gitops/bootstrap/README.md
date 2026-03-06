GitOps bootstrap
----------------

This folder contains seed manifests for bootstrapping a GitOps controller (ArgoCD) and examples for secrets operators.

- `argocd-bootstrap.yaml` — lightweight ArgoCD `Application` that points the controller at `deploy/gitops` in this repo.
- `../external-secrets/example-externalsecret.yaml` — example `ExternalSecret` that fetches MinIO credentials from Vault.

Usage:

1. Install the GitOps controller (ArgoCD/Flux) into the cluster.
2. Apply `argocd-bootstrap.yaml` to point the controller at this repository path.
3. Install ExternalSecrets operator and configure a `ClusterSecretStore` named `vault-backend` per `docs/GITOPS_VAULT_GUIDE.md`.
