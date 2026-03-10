# Phase P4: Network Hardening for Multi-Tenant Runners

## Why it matters
Phase P4 is about delivering isolation between tenant runner pools while keeping the supply chain trust model intact. This doc explains how the `multi-tenant-runners` Terraform module and the accompanying network-policy generator can lock down ingress/egress for each tenant.

## Hardened Terraform module
- **Tags & labels**: Each template automatically receives `runner`, `tenant:<id>`, and `phase-p4` tags plus any custom labels you supply. Firewall resources use the tags to pin the perimeter.
- **Firewall rules**: A deny-all ingress/egress baseline is created, and explicit allow-lists are added only when you provide CIDRs via `allowed_ingress_cidrs` and `allowed_egress_cidrs`.
- **Service accounts & metadata**: Supply `service_account_email` if the tenant runners need scoped GCP privileges. You can override the bootstrapper using `custom_startup_script` so that Argent-runner registration, telemetry hooks, or vault enrollments happen before the runner registers with GitHub.
- **Outputs**: After `terraform apply`, read `runner_template_self_link`, `ingress_firewall_name`, and `egress_firewall_name` to correlate the hardened resources with downstream monitoring tools.

## Generating NetworkPolicy manifest
1. Run the helper script with the tenant ID and optional output path:
   ```bash
   scripts/security/network-policy/apply-egress-rules.sh tenant-a /tmp/netpol-tenant-a.yaml
   ```
2. The script looks for the following environment variables (comma-separated lists are accepted):
   - `ALLOWED_INGRESS_CIDRS` (default: `10.30.0.0/16`)
   - `ALLOWED_INGRESS_PORTS` (default: `443`)
   - `ALLOWED_EGRESS_CIDRS` (includes registry CIDRs + metadata by default)
   - `ALLOWED_EGRESS_PORTS` (default: `443,80`)
3. Apply the generated manifest in the appropriate namespace with `kubectl apply -f /tmp/netpol-tenant-a.yaml` after reviewing the CIDRs and ports for the tenant.
4. To extend the manifest for additional pods or namespaces, edit the YAML by duplicating sections and replacing `namespace` or `podSelector` selectors.

## Recommended workflow
1. Duplicate `terraform/environments/staging-tenant-a/main.tf`, adjust `tenant_id`, `runner_group_name`, and CIDRs for the new tenant.
2. Run `terraform init && terraform apply` from the environment directory to create isolated templates and firewalls.
3. Export `ALLOWED_*` variables for the new tenant and run `scripts/security/network-policy/apply-egress-rules.sh`. Review the policy in a staging cluster before rolling out to production.
4. Monitor logs for blocked traffic (e.g., VPC Flow Logs, Calico events) to ensure the deny-all baseline is not impacting essential services. Iterate by adding CIDRs or ports if legitimate traffic is dropped.

## Verification checklist
- [ ] Firewall allow-lists match the actual registry/service endpoints needed by the runner images.
- [ ] Metadata server (`169.254.169.254/32`) remains reachable (handled by `required_egress_cidrs`).
- [ ] GitHub self-hosted runner token injection still works (`custom_startup_script`).
- [ ] Kubernetes namespaces for tenants are labeled/tagged similarly so that generated NetworkPolicy manifests can be reused.

## Next steps
- Wire the module outputs into Vault or monitoring dashboards.
- Extend the script to push manifests to a GitOps repo if tenants require GitOps-managed policies.
- Pair with `scripts/supplychain/` to ensure signed images are used inside these hardened pools.
