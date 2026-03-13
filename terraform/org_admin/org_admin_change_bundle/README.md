Org Admin Change Bundle
=======================

Purpose
-------
This bundle contains the exact artifacts and commands required to complete the remaining org-level approvals for NexusShield production and staging. It is intended for an org administrator to review, sign, and apply from a trusted admin bastion.

What is included
----------------
- `org_level_vpc_peering_policy.json` — org-policy JSON to allow VPC peering for production (example). Review before applying.
- `apply_org_level_changes.sh` — script with `--dry-run` and `apply` modes to set org policies and provide verification commands.
- `vault_approle_instructions.md` — Vault AppRole provisioning steps for Vault admins.
- `aws_objectlock_instructions.md` — AWS S3 Object Lock guidance for AWS org admins.

Important
---------
- These actions modify organization-level policy and must be executed by a user with `roles/resourcemanager.organizationAdmin` and `roles/orgpolicy.policyAdmin`.
- Review each file and confirm with security/ops team before applying.

Quick usage (review and then run as org admin):

```bash
# review files
less terraform/org_admin/org_admin_change_bundle/README.md
less terraform/org_admin/org_admin_change_bundle/org_level_vpc_peering_policy.json

# dry-run (shows planned changes)
bash terraform/org_admin/org_admin_change_bundle/apply_org_level_changes.sh --dry-run

# apply (will set org policy and print verification commands)
bash terraform/org_admin/org_admin_change_bundle/apply_org_level_changes.sh --apply
```
