Ansible role to ensure the Caddy `gitlab.internal.elevatediq.com` site block
is present in `/etc/caddy/Caddyfile.portal.elevatediq` and restart the `eiq-caddy`
container.

Usage:

- Set variables as needed in inventories or extra-vars:
  - `gitlab_upstream` (default `172.17.0.1:8929`)
  - `gitlab_host` (default `192.168.168.42`)
  - `tls_cert` and `tls_key` (paths on the host)

This role is idempotent and intended for ephemeral, automated remediation.
