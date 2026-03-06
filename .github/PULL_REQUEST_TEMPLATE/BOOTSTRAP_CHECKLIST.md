<!-- PR Template: Use this for GitOps / secret bootstrap PRs -->

## Summary

Describe what this PR bootstraps (ArgoCD/Flux, SealedSecret, ClusterSecretStore, MinIO artifact, etc.) and link the related SOV issue.

## Checklist (required for merge)

- [ ] Linked to tracking issue: SOV-007* or relevant epic
- [ ] No plaintext secrets committed in this PR
- [ ] If any `SealedSecret` files are committed, confirm the `kubeseal` public key used to create them matches the **target cluster's** SealedSecrets controller
- [ ] If using artifact storage (MinIO), confirm artifact URL and ACLs and that artifacts are accessible to ops only
- [ ] Vault AppRole created and `role_id` validated; `secret_id` handled out-of-band (not in repo)
- [ ] CI workflow validated on a self-hosted runner with kubeconfig access (no secrets printed)
- [ ] Security team review/approval (name + timestamp)
- [ ] Platform/ops reviewer assigned and approval recorded
- [ ] Add rollback instructions and staging validation steps
- [ ] Update relevant docs in `docs/` (link files changed)

## Testing and Validation

Describe how this was validated in staging (kubectl/flux/argocd sync logs, ExternalSecrets retrieval test, MinIO object access test).

## Rollout Plan

1. Merge to `main` after approvals
2. Apply in staging via GitOps controller and validate
3. Promote to production following ops runbook

## Security Notes

Any comments for auditors: TTLs used, rotation plan, approver names.
