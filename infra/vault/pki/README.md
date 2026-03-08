# Vault PKI Terraform Scaffold

This folder contains a scaffold for provisioning a Vault PKI mount and roles used to issue mTLS certificates for the control-plane (Envoy) and runners.

This is a scaffold — do not apply without reviewing and configuring Vault provider authentication and ACLs.

Files:
- `main.tf` — sample Vault resources for PKI mount and role

Security notes:
- Use Vault ACLs and short-lived tokens for automation.
- Protect Terraform state containing Vault mounts with a secure backend and encryption (e.g., GCS/AWS S3 + KMS).
