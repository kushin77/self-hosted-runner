GitOps Skeleton

Structure

- gitops-infra/
- gitops-apps/
- gitops-catalog/

Next steps

1. Populate `gitops-infra` with cluster bootstrap manifests and platform operator manifests.
2. Populate `gitops-catalog` with Helm/Kustomize templates for teams.
3. Connect ArgoCD/Flux to these repositories.