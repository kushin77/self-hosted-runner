# Task: Terraform CI job to consume AMI and run plan

- Related Epic: SOV-004
- Status: in-progress
- Owner: Infra

## Objective
Add a workflow that downloads the `ami.tfvars` artifact produced by the Packer job and runs `terraform plan` for the `ci-runners` module. This creates a reviewed plan artifact without automatically applying infrastructure changes.

## Checklist
- [x] Add workflow `.github/workflows/terraform-plan-ami.yml` to run on `workflow_run` of the Packer job.
- [ ] Add downstream promotion/apply job (manual approval) if plan is accepted.
