# Task: Manual Terraform apply workflow for CI runners

- Related Epic: SOV-004
- Status: in-progress
- Owner: Infra

## Objective
Add a protected manual `workflow_dispatch` job that applies a previously produced terraform plan artifact. Uses GitHub environment protection (`production`) to require approvers.

## Checklist
- [x] Add `.github/workflows/terraform-apply.yml`.
- [ ] Ensure repository `production` environment has required reviewers configured.
- [ ] After approval, run and validate created instances in staging before promoting to prod.
