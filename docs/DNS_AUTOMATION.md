DNS Automation Guidance

This document describes the recommended automation to create an authoritative DNS A record for `gitlab.internal.elevatediq.com`.

Options:
- Route53: add implementation using `community.aws.route53` Ansible modules and store AWS credentials in Ansible Vault or environment.
- Cloudflare: add implementation using `community.cloudflare.cloudflare_dns` and an API token stored securely.
- Manual: write an intent artifact with the desired change (used by current playbook default).

Files added:
- `ansible/roles/dns_record` — role skeleton with manual intent writer and provider placeholders.
- `playbooks/provision_dns_record.yml` — run the role locally to provision DNS when credentials are present.

Recommended next steps:
1. If you manage DNS via Terraform, add a proper `aws_route53_record` or equivalent resource and place it under `terraform/` as part of immutable IaC.
2. If you prefer Ansible, provide provider credentials and replace the placeholder tasks with actual provider modules.
3. After DNS is in place, remove temporary `/etc/hosts` automation and close `issues/0001-gitlab-unreachable.md` if not already closed.
