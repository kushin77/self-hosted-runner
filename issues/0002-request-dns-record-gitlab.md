---
Title: Request authoritative DNS A record for GitLab internal
Status: open
Created: 2026-03-06

Summary:

Please create an authoritative DNS A record for `gitlab.internal.elevatediq.com` pointing to `192.168.168.42` in the `internal.elevatediq.com` zone. This will replace the temporary `/etc/hosts` workaround and restore normal resolution for operators.

Details:

- Host: gitlab.internal.elevatediq.com
- A record: 192.168.168.42
- TTL: 300 (recommended)
- Reason: NXDOMAIN observed from runners and operator workstations; temporary remediation applied via Ansible role and Caddy proxy fix documented in `docs/CADDY_GITLAB_AUTOMATION.md`.

Action items:

1. DNS team: please add the A record in the internal DNS service and confirm propagation.
2. After confirmation, run `ansible-playbook playbooks/remove_hosts_entry.yml` (or the previously added hosts role) to remove temporary `/etc/hosts` entries.
3. Close this issue once authoritative DNS resolves and the hosts automation is removed.

References:

- Incident: issues/0001-gitlab-unreachable.md
- Automation: ansible/roles/dns_record and playbooks/provision_dns_record.yml
