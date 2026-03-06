DNS Record Role

Purpose: idempotent role to create/ensure a DNS A record exists for a given provider.

Supported providers: route53 (via community.aws), cloudflare (via community.cloudflare) — both require provider credentials configured in environment or Ansible vault.

Usage (example):

- hosts: localhost
  roles:
    - role: dns_record
      vars:
        dns_provider: route53
        dns_zone: internal.elevatediq.com
        dns_name: gitlab.internal.elevatediq.com
        dns_ttl: 300
        dns_value: 192.168.168.42

If no provider is available, the role will write a small review file with the intended change to `artifacts/dns-intent/`.
