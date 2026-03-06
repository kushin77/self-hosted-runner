---
name: Terraform: Invalid modules found
about: Aggregated report of Terraform validation failures to triage infra modules
---

### Summary

The repository validation detected multiple Terraform modules that failed `terraform validate` or could not be initialized locally. This issue aggregates the failures and suggests next steps.

<!-- TEMPLATE: Replace placeholders with real data when filing -->

**Detected invalid modules (examples):**
- `terraform/examples/azure-scale`
- `terraform/provision/postgres`
- `terraform/provision/redis`
- `terraform/provision/harbor-integration`
- `terraform/environments/staging-tenant-a`
- `terraform/vault`
- `terraform/modules/multi-tenant-runners`
- `terraform/modules/ephemeral-runner-template`
- `terraform/modules/workload-identity`
- `terraform/modules/airgap-control-plane`
- `terraform/modules/azure_scale_set`
- `terraform/minio`
- `terraform/harbor`

**Observed issues:**
- `INIT_FAIL` where `terraform init -backend=false` failed (possible missing provider plugins or network issues)
- `INVALID` indicates `terraform validate` failed locally (syntax, variable, or provider issues)

**Suggested next steps:**
1. Assign owners for each module (use `CODEOWNERS` if available).
2. For `INIT_FAIL` entries: run `terraform init -backend=false` in that module and capture errors; verify provider requirements and provider version constraints.
3. For `INVALID` entries: run `terraform validate -no-color` and capture output; fix syntax or variable references.
4. Add CI checks to run `terraform init -backend=false` and `terraform validate` for each module.
5. If module depends on external state, add example minimal `terraform.tfvars` for local validation.

**Automation tip:** Use `scripts/automation/terraform/validate_all.sh` to run validates across modules and collect outputs (I can add this script if helpful).

Please triage these modules and update this issue with owners and estimated ETA for fixes.
