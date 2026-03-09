# Task: GitOps controller + Vault integration

- Related Epic: SOV-007
- Status: in-progress
- Owner: Platform

## Objective
Deploy a GitOps controller (ArgoCD or Flux), integrate it with Vault for secret delivery, and add manifest validation to Draft issues.

## Checklist
- [x] Add GitOps guidance `deploy/gitops/README.md` and `docs/GITOPS_VAULT_GUIDE.md`.
- [x] Add manifest validation workflow `.github/workflows/validate-manifests.yml`.
- [ ] Create bootstrap manifests for ArgoCD/Flux and secure repo access via Vault.
- [ ] Test GitOps workflows and fail open/closed behavior in staging.
