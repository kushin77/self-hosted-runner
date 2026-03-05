Phase P4 — AWS Spot Runner: Readiness Notice

Status: READY for Ops execution

Summary:
- Code merged to `main`: Terraform module `aws_spot_runner`, Lambda handler, CI workflows (plan + guarded apply).
- Ops automation added: `scripts/ops/p4-aws-spot-setup.sh` (init/validate/plan helper).
- Verification and handoff docs added: `docs/PHASE_P4_AWS_SPOT_HANDOFF.md`, `docs/PHASE_P4_AWS_SPOT_VERIFICATION.md`.

Blocking inputs required from Ops (please provide):
1. Repo secrets: `AWS_ROLE_TO_ASSUME` (or CI credentials) and `AWS_REGION`.
2. `terraform/examples/aws-spot/terraform.tfvars` with `vpc_id` and `subnet_ids` (or supply via workflow variables).
3. Protect the `prod-terraform-apply` environment in GitHub for guarded apply.

References: PR #276, master tracker #240, Ops request #287 (created), escalation #279 (closed).

Next actions by automation once inputs provided:
- Re-run `p4-aws-spot-deploy-plan.yml` and upload plan artifact.
- Summarize plan and request approval.
- Proceed with guarded apply when `prod-terraform-apply` approval is granted.

Contact: platform@your-org or reopen issue #287 to notify me.
