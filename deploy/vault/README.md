# Vault Helm chart (scaffold)

Minimal scaffold for deploying HashiCorp Vault. This is intended as a starting point for CI and integration work. Production deployments must configure:

- Storage backend (Consul, etcd, or cloud KMS)
- Auto-unseal (KMS, transit or AWS KMS)
- TLS and authentication
- High-availability and backup/restore

Follow-ups will add Helm hooks, init containers for unseal, and examples for injector patterns.
