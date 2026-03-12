# Release Notes — 2026-03-12

Summary:
- Phase 1: Deployer service-account key rotation automation deployed via systemd timer. Daily rotation scheduled at 02:00 UTC. Immutable audit trail enabled.
- Phase 2: AWS OIDC federation deployed (GitHub OIDC provider + `github-oidc-role`) in account 830916170067 (us-east-1). Terraform state imported and validated.

Notable commits:
- aaeebac43 — test(aws-oidc): robustly detect GitHub OIDC provider in trust policy
- 8f9359a61 — feat(aws-oidc): Phase 2 AWS OIDC Federation deployed
- 777562d7e — docs(cert): Deployment Readiness Certificate

Artifacts:
- Audit logs: `logs/multi-cloud-audit/owner-rotate-*.jsonl`, `logs/aws-oidc-deployment-*.jsonl`
- Ops docs: `DEPLOYER_KEY_ROTATION_OPS_GUIDE.md`, `DEPLOYMENT_READINESS_CERTIFICATE_20260312.md`, `DELIVERY_HANDOFF_20260312.md`
- Terraform: `infra/terraform/modules/aws_oidc_federation/`

Release tag: `v2026.03.12-oidc`

Operator notes:
- This release was deployed directly to `main` under lead-engineer authority (akushnir). No PRs or GitHub Actions were used to perform the initial deployment operations.
- Monitor `sudo journalctl -u deployer-key-rotate.service -f` and CloudTrail for OIDC usage.
