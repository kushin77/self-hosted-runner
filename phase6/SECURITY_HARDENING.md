# Security Hardening (Advanced) — Phase 6

Areas covered:
- RBAC tightening and least-privilege enforcement
- NetworkPolicies for Kubernetes workloads
- Secrets rotation automation (GSM/Vault/KMS)
- Automated vulnerability scanning (container images, IaC)

Automation artifacts:
- `scripts/phase6/rbac_enforce.sh` — audit current RBAC, apply tightened policies via kubectl
- `scripts/phase6/network_policies_apply.sh` — apply default-deny network policies and necessary allow-lists
- `scripts/phase6/rotate_secrets.sh` — orchestrate secrets rotation across GSM/Vault/KMS
