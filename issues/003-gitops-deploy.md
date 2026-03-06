Title: Adopt GitOps for declarative, auditable deploys
Status: open
Assignee: TBD

Description:
- Implement a small GitOps reconciler for single-host deployments or use ArgoCD/Flux for clusters.
- Keep deployment manifests in a dedicated `deploy/` directory and reconcile to target host.
- Add signed commits and automated policy checks before reconciliation.

Acceptance criteria:
- Deployment state is derivable from a Git ref and is automatically reconciled.
