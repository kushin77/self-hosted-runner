Title: Phase 4.4 - Compliance module activation blocked by `cloud-audit` group

Description:
- Compliance module activation requires `cloud-audit` IAM group to exist for audit bindings.
- Until org creates the `cloud-audit` group, module cannot be fully enabled.

Acceptance Criteria:
- `cloud-audit` group created and accessible to project-level IAM bindings.
- Compliance module in `infra/terraform/modules/compliance` can be enabled and validated via Terraform.

Notes:
- Follow org governance to request group creation; add checklist for preflight steps in the module README.
