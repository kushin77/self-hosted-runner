Issue #259 - Credential Provisioning / Vault Agent Deployment

Status: blocked

Summary:
- Vault Agent deployed to bastion and configured with AppRole auto_auth.
- AppRole Role ID present at `/etc/vault/role-id.txt`.
- Secret ID updated to `/etc/vault/secret-id.txt` and secured.

Observed blockers:
1. AppRole `role_id` is invalid on the local Vault instance (HTTP 400 "invalid role ID").
   - Likely cause: AppRole was created on a different Vault cluster or Vault was reinitialized.
   - Fix options: (A) point the agent to the original Vault cluster (restore DNS/hosts for `vault.service.consul`), or (B) recreate AppRole on this Vault instance (requires a Vault management token).
2. Phase 2 (AWS) is still pending because AWS CLI credentials are not configured on operator side.

Next actions (recommendation):
- Provide the operator decision: restore DNS for `vault.service.consul` OR provide a Vault management token so I can create a new AppRole and Secret ID on the local Vault.
- Operator to supply AWS credentials (via `aws configure` or env vars) so I can run `./scripts/operator-aws-provisioning.sh`.

Audit trail: see `logs/deployment-provisioning-audit.jsonl` and `DEPLOYMENT_VAULT_AGENT_STATUS_FINAL.md` for detailed steps performed.
