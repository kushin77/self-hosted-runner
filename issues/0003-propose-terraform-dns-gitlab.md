---
Title: Propose Terraform Route53 record for gitlab.internal.elevatediq.com
Status: open
Created: 2026-03-06

Summary:

This proposes adding an immutable Terraform Route53 record for `gitlab.internal.elevatediq.com` pointing to `192.168.168.42`. The module skeleton is added under `terraform/modules/dns/gitlab`.

Action items:

1. Review the Terraform module in `terraform/modules/dns/gitlab` and confirm `zone_id` and provider configuration strategy.
2. If approved, apply via the normal Terraform CI workflow or locally after configuring backend and credentials.
3. After DNS propagation, run `ansible-playbook playbooks/remove_hosts_entry.yml -i inventories/runners` to remove the temporary hosts entries.

References:

- Automation: ansible/roles/dns_record and playbooks/provision_dns_record.yml
- Incident: issues/0001-gitlab-unreachable.md
