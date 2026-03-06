Flux bootstrap variant
---------------------

This document shows how to bootstrap Flux (v2) to point at this repository's `deploy/gitops` folder.

1) Install Flux controllers on the cluster (run from a machine with `flux` CLI and kubeconfig):

```bash
flux install
```

2) Apply the bootstrap GitRepository and Kustomization in `flux-system`:

```bash
kubectl apply -f deploy/gitops/bootstrap/flux-bootstrap.yaml
```

3) Optionally, to bootstrap secrets safely use Sealed Secrets:

- Create unsealed `vault-approle-secret` locally (do not commit). See `sealed-approle-secret-template.md`.
- Seal it with `kubeseal` and commit the resulting `sealed-vault-approle-secret.yaml` into `deploy/gitops/bootstrap`.

4) After Flux syncs, it will apply manifests under `deploy/gitops` using the Kustomization above.

Notes:
- Ensure the Flux controllers are installed with permissions to read `SealedSecret` objects if using SealedSecrets.
- Validate the `path` and `ref.branch` in `flux-bootstrap.yaml` to match your desired branch.
