CA Distribute Role

Purpose: idempotently distribute an internal CA certificate to managed hosts and install it into the system trust store.

Supported systems: Debian/Ubuntu (uses /usr/local/share/ca-certificates/ and update-ca-certificates). You can extend to RHEL/CentOS by adding the appropriate tasks.

Usage example in a playbook:

- hosts: operators
  roles:
    - role: ca_distribute
      vars:
        ca_local_path: files/eiq-internal-ca.crt
        ca_dest_name: eiq-internal-ca.crt
