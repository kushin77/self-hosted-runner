GitOps controller deployment notes
================================

This folder documents recommended approaches to deploy a GitOps controller (ArgoCD or Flux) within the sovereign platform.

Recommendations
---------------
- Use ArgoCD for a UI-driven Apps-of-Apps pattern if you need an admin UI and multi-cluster management.
- Use Flux for lightweight, policy-driven GitOps with strong integration to Helm and Kustomize.
- Keep GitOps controller manifests in a dedicated repo or a top-level `deploy/gitops` directory.

Bootstrap steps (example - ArgoCD)
--------------------------------
1. Install ArgoCD into `gitops` namespace using the hardened Helm chart.
2. Configure the repository credentials (SSH keys) stored in Vault; inject them into ArgoCD via sealed secrets or ExternalSecrets.
3. Create an `app-of-apps` that points to `deploy/` to reconcile namespaces and apps.

Secrets & Vault
---------------
- Store ArgoCD admin credentials and repository SSH keys in Vault.
- Use Vault Agent or ExternalSecrets to populate Kubernetes Secrets for ArgoCD to use.

Operability
-----------
- Enable automated health checks and alerts in the observability stack for GitOps controllers.
- Use role-based access to control which teams can update GitOps manifests.
