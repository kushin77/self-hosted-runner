## GitLab internal hostname unreachable

**Summary**

When attempting to access the internal GitLab URL `https://gitlab.internal.elevatediq.com` the browser returns DNS NXDOMAIN. I ran diagnostics from the runner host to capture the issue and gather data for remediation.

**Diagnostics (collected on runner host)**

==nslookup==
Server:         127.0.0.53
Address:        127.0.0.53#53

** server can't find gitlab.internal.elevatediq.com: NXDOMAIN

==dig==

==host==
Host gitlab.internal.elevatediq.com not found: 3(NXDOMAIN)

==getent==

==python==
ERROR [Errno -2] Name or service not known

==/etc/hosts==
127.0.0.1 localhost
127.0.1.1 dev-elevatediq-2

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
192.168.168.1 firewalla firewalla.local

==repo-grep==
./scripts/scm/gitlab-github-sync.sh:10:#   GITLAB_HOST          — GitLab hostname (e.g. gitlab.internal.elevatediq.com)
./scripts/scm/gitlab-github-sync.sh:22:GITLAB_HOST="${GITLAB_HOST:-gitlab.internal.elevatediq.com}"

==ping==
ping: gitlab.internal.elevatediq.com: Name or service not known

==curl==
curl: (6) Could not resolve host: gitlab.internal.elevatediq.com

**Immediate findings**

- The hostname `gitlab.internal.elevatediq.com` does not resolve from this host (NXDOMAIN).
- No static override exists in `/etc/hosts` on the runner.
- The repo defaults to that hostname in `scripts/scm/gitlab-github-sync.sh`.

**Recommended next actions (order-of-operations)**

1. Confirm the authoritative internal DNS zone for `internal.elevatediq.com` is online and serving records for `gitlab`.
2. If the server IP is known and DNS will take time, add a short-term `/etc/hosts` entry on affected hosts (automate via Ansible inventory) to point `gitlab.internal.elevatediq.com` to the known IP. Example:

   10.0.0.42 gitlab.internal.elevatediq.com

3. Search infrastructure (Terraform/Ansible/packer) for a declared GitLab host and verify its IP and DNS records. If missing, open a change request to provision DNS record.
4. As a long-term fix, ensure DNS is managed and immutable via IaC (Terraform for DNS), and include healthchecks and alerting for zone availability.

**Actions I will take now (with your approval)**

- (A) Search repo for any inventory or infra entries containing GitLab server IP and attempt to validate and create a hosts-entry PR/Ansible patch.
- (B) Create a locked issue in the repo (this file) — created.
- (C) If you confirm the GitLab server IP, I can open a PR that adds an Ansible task to manage `/etc/hosts` entries for affected hosts until DNS is fixed.

**Notes**

This issue file was created automatically by the runner diagnostics workflow. Close this issue once DNS is repaired and the temporary hosts automation is removed.
