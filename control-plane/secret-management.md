# Secret Management & Key Management Guidance

Goal: Ensure immutable, ephemeral, idempotent, no-ops automation integrating GSM (Google Secret Manager), Vault, and KMS.

Recommended patterns:
- Store runtime secrets in GSM or Vault; use KMS for envelope encryption where required.
- Keep infrastructure immutable: build images with baked-in agent and configuration, provision via Terraform.
- Use short-lived credentials: workload identity (GCP), STS roles (AWS), Azure Managed Identity.
- Idempotent provisioning: Terraform state-driven resources, avoid imperative scripts that mutate state outside Terraform.
- No-ops deploys: include pre-checks that exit successfully if target state matches desired state.

Integration ideas:
- Use Vault Agent or application-level SDK to fetch secrets at startup, not baked into images.
- Use in-place rotation hooks: update secret in Vault/GSM and trigger instance image rotation via control plane.
